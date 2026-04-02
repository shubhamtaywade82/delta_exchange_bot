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
end
