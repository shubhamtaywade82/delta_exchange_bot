# frozen_string_literal: true

begin
  require "ollama-client"
  OLLAMA_GEM_AVAILABLE = true
rescue LoadError
  OLLAMA_GEM_AVAILABLE = false
end
require "json"
require "net/http"
require "timeout"
require "uri"

module Ai
  # OllamaClient provides cached access to local Ollama model responses for meta-configuration only.
  class OllamaClient
    def self.client
      raise LoadError, "ollama-client gem is unavailable" unless OLLAMA_GEM_AVAILABLE

      @client ||= Ollama.new(url: base_url)
    end

    # @param prompt [String]
    # @return [String]
    def self.ask(prompt)
      with_retries do
        Timeout.timeout(request_timeout_seconds) do
          if api_key_present?
            request_via_http(prompt)
          else
            request_via_gem(prompt)
          end
        end
      end
    end

    def self.request_via_gem(prompt)
      response = client.generate(
        model: model_name,
        prompt: prompt,
        stream: false
      )
      response.fetch("response").to_s
    end

    def self.request_via_http(prompt)
      uri = generate_uri
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = request_timeout_seconds
      http.read_timeout = request_timeout_seconds

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{api_key}"
      req.body = { model: model_name, prompt: prompt, stream: false }.to_json

      response = http.request(req)
      raise "Ollama HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      payload.fetch("response").to_s
    end

    def self.with_retries
      attempts = 0
      begin
        attempts += 1
        yield
      rescue StandardError => e
        raise if attempts > max_retries

        sleep(0.2 * attempts)
        retry
      end
    end

    def self.base_url
      Trading::RuntimeConfig.fetch_string("ai.ollama_url", default: "http://localhost:11434", env_key: "OLLAMA_URL").presence ||
        ENV["OLLAMA_BASE_URL"] ||
        "http://localhost:11434"
    end

    def self.model_name
      Trading::RuntimeConfig.fetch_string("ai.ollama_model", default: "llama3", env_key: "OLLAMA_MODEL").presence ||
        ENV["OLLAMA_AGENT_MODEL"] ||
        "llama3"
    end

    def self.request_timeout_seconds
      Trading::RuntimeConfig.fetch_integer("ai.ollama_timeout_seconds", default: 8, env_key: "OLLAMA_TIMEOUT_SECONDS")
    end

    def self.max_retries
      Trading::RuntimeConfig.fetch_integer("ai.ollama_max_retries", default: 2, env_key: "OLLAMA_MAX_RETRIES")
    end

    def self.api_key_present?
      api_key.to_s.strip != ""
    end

    def self.api_key
      Trading::RuntimeConfig.fetch_string("ai.ollama_api_key", default: ENV["OLLAMA_API_KEY"], env_key: "OLLAMA_API_KEY")
    end

    def self.generate_uri
      url = base_url
      return URI(url) if url.end_with?("/api/generate")

      URI("#{url.chomp('/')}/api/generate")
    end
  end
end
