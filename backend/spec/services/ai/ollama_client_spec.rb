# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::OllamaClient do
  describe ".resolved_base_url" do
    OLLAMA_ENV_KEYS = %w[
      OLLAMA_BASE_URL OLLAMA_URL OLLAMA_API_KEY OLLAMA_MODEL OLLAMA_AGENT_MODEL
    ].freeze

    around do |example|
      saved = OLLAMA_ENV_KEYS.to_h { |k| [k, ENV[k]] }
      OLLAMA_ENV_KEYS.each { |k| ENV.delete(k) }
      example.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    def stub_runtime(url:, key:, force_local: false)
      allow(Trading::RuntimeConfig).to receive(:fetch_string) do |k, **_opts|
        case k
        when "ai.ollama_url" then url
        when "ai.ollama_api_key" then key
        else ""
        end
      end
      allow(Trading::RuntimeConfig).to receive(:fetch_integer) do |k, **_opts|
        case k
        when "ai.ollama_timeout_seconds" then 90
        when "ai.ollama_max_retries" then 2
        else 0
        end
      end
      allow(Trading::RuntimeConfig).to receive(:fetch_boolean)
        .with("ai.ollama_force_local", hash_including(default: false, env_key: "OLLAMA_FORCE_LOCAL"))
        .and_return(force_local)
    end

    it "uses Ollama Cloud when OLLAMA_API_KEY is set and URL is localhost" do
      ENV["OLLAMA_API_KEY"] = "cloud-key"
      stub_runtime(url: "http://localhost:11434", key: "")
      expect(described_class.__send__(:resolved_base_url)).to eq("https://ollama.com")
    end

    it "uses Ollama Cloud when only DB api key and localhost URL" do
      stub_runtime(url: "http://localhost:11434", key: "cloud-key")
      expect(described_class.__send__(:resolved_base_url)).to eq("https://ollama.com")
    end

    it "uses explicit non-local URL when set even with API key" do
      stub_runtime(url: "https://custom.example/v1", key: "k")
      expect(described_class.__send__(:resolved_base_url)).to eq("https://custom.example/v1")
    end

    it "uses localhost when no API key and URL is localhost" do
      stub_runtime(url: "http://127.0.0.1:11434", key: "")
      expect(described_class.__send__(:resolved_base_url)).to eq("http://127.0.0.1:11434")
    end

    it "respects force_local with API key" do
      stub_runtime(url: "http://localhost:11434", key: "k", force_local: true)
      expect(described_class.__send__(:resolved_base_url)).to eq("http://localhost:11434")
    end

    it "prefers OLLAMA_BASE_URL over DB url" do
      ENV["OLLAMA_BASE_URL"] = "https://api.example"
      ENV["OLLAMA_API_KEY"] = "x"
      stub_runtime(url: "http://localhost:11434", key: "")
      expect(described_class.__send__(:resolved_base_url)).to eq("https://api.example")
    end
  end

  describe "OLLAMA_TIMEOUT_SECONDS / OLLAMA_MAX_RETRIES" do
    around do |example|
      saved = %w[OLLAMA_TIMEOUT_SECONDS OLLAMA_MAX_RETRIES].to_h { |k| [k, ENV[k]] }
      %w[OLLAMA_TIMEOUT_SECONDS OLLAMA_MAX_RETRIES].each { |k| ENV.delete(k) }
      example.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "uses OLLAMA_TIMEOUT_SECONDS without reading ai.ollama_timeout_seconds from RuntimeConfig" do
      ENV["OLLAMA_TIMEOUT_SECONDS"] = "200"
      expect(Trading::RuntimeConfig).not_to receive(:fetch_integer).with(
        "ai.ollama_timeout_seconds",
        anything
      )
      expect(described_class.__send__(:read_timeout_seconds)).to eq(200)
    end

    it "uses RuntimeConfig for timeout when OLLAMA_TIMEOUT_SECONDS is unset" do
      allow(Trading::RuntimeConfig).to receive(:fetch_integer)
        .with(
          "ai.ollama_timeout_seconds",
          hash_including(default: Ai::OllamaClient::DEFAULT_TIMEOUT_SECONDS, env_key: nil)
        )
        .and_return(42)
      expect(described_class.__send__(:read_timeout_seconds)).to eq(42)
    end

    it "uses OLLAMA_MAX_RETRIES without reading ai.ollama_max_retries from RuntimeConfig" do
      ENV["OLLAMA_MAX_RETRIES"] = "0"
      expect(Trading::RuntimeConfig).not_to receive(:fetch_integer).with(
        "ai.ollama_max_retries",
        anything
      )
      expect(described_class.__send__(:read_max_retries)).to eq(0)
    end
  end
end
