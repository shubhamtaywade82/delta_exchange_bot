# frozen_string_literal: true

begin
  require "ollama_client"
  OLLAMA_GEM_AVAILABLE = true
rescue LoadError
  OLLAMA_GEM_AVAILABLE = false
end
require "timeout"
require "uri"

module Ai
  # Uses ollama-client (Ollama::Client + Ollama::Config). Supports Ollama Cloud: https://ollama.com + API key.
  class OllamaClient
    CLOUD_BASE_URL = "https://ollama.com"
    DEFAULT_LOCAL_URL = "http://localhost:11434"

    class << self
      # @param prompt [String]
      # @return [String]
      def ask(prompt)
        raise LoadError, "ollama-client gem is unavailable" unless OLLAMA_GEM_AVAILABLE

        with_retries do
          Timeout.timeout(request_timeout_seconds) do
            ollama_client.generate(prompt: prompt, model: model_name, strict: false)
          end
        end
      end

      def ollama_client
        Ollama::Client.new(config: build_config)
      end

      def build_config
        cfg = Ollama::Config.new
        cfg.base_url = resolved_base_url
        key = api_key
        cfg.api_key = key if key.present?
        cfg.model = model_name
        cfg.timeout = request_timeout_seconds
        cfg.retries = max_retries
        cfg.strict_json = false
        cfg
      end

      def resolved_base_url
        url = configured_base_url.to_s.strip.chomp("/")
        if force_local_ollama?
          return url.presence || DEFAULT_LOCAL_URL
        end

        if api_key_present? && (url.blank? || localhost_url?(url))
          CLOUD_BASE_URL
        elsif url.present?
          url
        else
          DEFAULT_LOCAL_URL
        end
      end

      # ENV wins over DB `Setting` rows so deployment/.env overrides seeded defaults (OLLAMA_URL is the DB env_key).
      def configured_base_url
        ENV["OLLAMA_BASE_URL"].presence ||
          ENV["OLLAMA_URL"].presence ||
          db_or_default_ollama_url
      end

      def db_or_default_ollama_url
        Trading::RuntimeConfig.fetch_string("ai.ollama_url", default: "", env_key: nil).to_s.strip
      end

      def force_local_ollama?
        Trading::RuntimeConfig.fetch_boolean("ai.ollama_force_local", default: false, env_key: "OLLAMA_FORCE_LOCAL")
      end

      def localhost_url?(url)
        uri = URI.parse(url.to_s.strip)
        host = uri.host&.downcase
        host.nil? || host == "localhost" || host == "127.0.0.1" || host == "::1"
      rescue URI::InvalidURIError
        false
      end

      def with_retries
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

      def model_name
        ENV["OLLAMA_AGENT_MODEL"].presence ||
          ENV["OLLAMA_MODEL"].presence ||
          Trading::RuntimeConfig.fetch_string("ai.ollama_model", default: "llama3", env_key: nil).presence ||
          "llama3"
      end

      def request_timeout_seconds
        timeout = Trading::RuntimeConfig.fetch_integer("ai.ollama_timeout_seconds", default: 8, env_key: "OLLAMA_TIMEOUT_SECONDS")
        timeout.positive? ? timeout : 8
      end

      def max_retries
        retries = Trading::RuntimeConfig.fetch_integer("ai.ollama_max_retries", default: 2, env_key: "OLLAMA_MAX_RETRIES")
        retries.negative? ? 0 : retries
      end

      def api_key_present?
        api_key.to_s.strip != ""
      end

      def api_key
        ENV["OLLAMA_API_KEY"].to_s.strip.presence ||
          Trading::RuntimeConfig.fetch_string("ai.ollama_api_key", default: "", env_key: nil).to_s.strip
      end
    end
  end
end
