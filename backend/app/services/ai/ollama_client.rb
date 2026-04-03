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
    # SMC / large prompts routinely exceed a few seconds on local CPUs; keep aligned with .env.example.
    DEFAULT_TIMEOUT_SECONDS = 90

    ConnectionSettings = Data.define(
      :request_timeout_seconds,
      :max_retries,
      :resolved_base_url,
      :model_name,
      :api_key
    ) do
      def api_key_present?
        api_key.to_s.strip != ""
      end
    end

    class << self
      # @param prompt [String]
      # @return [String]
      def ask(prompt, connection_settings: nil)
        raise LoadError, "ollama-client gem is unavailable" unless OLLAMA_GEM_AVAILABLE

        settings = connection_settings || read_connection_settings
        with_retries(max_retries: settings.max_retries) do
          Timeout.timeout(settings.request_timeout_seconds) do
            build_client(settings).generate(prompt: prompt, model: settings.model_name, strict: false)
          end
        end
      end

      def resolved_base_url
        read_connection_settings.resolved_base_url
      end

      def read_connection_settings
        url = configured_base_url_string
        api_key_value = read_api_key_string
        force_local = read_force_local_boolean
        ConnectionSettings.new(
          request_timeout_seconds: read_timeout_seconds,
          max_retries: read_max_retries,
          resolved_base_url: resolve_base_url(url, api_key_value, force_local),
          model_name: read_model_name_string,
          api_key: api_key_value
        )
      end

      def build_client(settings)
        cfg = Ollama::Config.new
        cfg.base_url = settings.resolved_base_url
        cfg.api_key = settings.api_key if settings.api_key_present?
        cfg.model = settings.model_name
        cfg.timeout = settings.request_timeout_seconds
        cfg.retries = settings.max_retries
        cfg.strict_json = false
        Ollama::Client.new(config: cfg)
      end

      def configured_base_url_string
        ENV["OLLAMA_BASE_URL"].presence ||
          ENV["OLLAMA_URL"].presence ||
          Trading::RuntimeConfig.fetch_string("ai.ollama_url", default: "", env_key: nil).to_s.strip
      end

      def read_force_local_boolean
        Trading::RuntimeConfig.fetch_boolean("ai.ollama_force_local", default: false, env_key: "OLLAMA_FORCE_LOCAL")
      end

      def resolve_base_url(url, api_key_value, force_local)
        url = url.to_s.strip.chomp("/")
        if force_local
          return url.presence || DEFAULT_LOCAL_URL
        end

        if api_key_value.present? && (url.blank? || localhost_url?(url))
          CLOUD_BASE_URL
        elsif url.present?
          url
        else
          DEFAULT_LOCAL_URL
        end
      end

      def localhost_url?(url)
        uri = URI.parse(url.to_s.strip)
        host = uri.host&.downcase
        host.nil? || host == "localhost" || host == "127.0.0.1" || host == "::1"
      rescue URI::InvalidURIError
        false
      end

      def with_retries(max_retries:)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue StandardError => e
          raise if e.is_a?(::Timeout::Error)
          raise if defined?(Ollama::TimeoutError) && e.is_a?(Ollama::TimeoutError)

          raise if attempts > max_retries

          sleep(0.2 * attempts)
          retry
        end
      end

      def read_model_name_string
        ENV["OLLAMA_AGENT_MODEL"].presence ||
          ENV["OLLAMA_MODEL"].presence ||
          Trading::RuntimeConfig.fetch_string("ai.ollama_model", default: "llama3", env_key: nil).presence ||
          "llama3"
      end

      # ENV wins over DB `settings` rows — matches ops expectation for `.env` and avoids stale seeded `8`
      # blocking `OLLAMA_TIMEOUT_SECONDS` from taking effect.
      def read_timeout_seconds
        if (raw = ENV["OLLAMA_TIMEOUT_SECONDS"].to_s.strip).present?
          v = Integer(raw)
          return v.positive? ? v : DEFAULT_TIMEOUT_SECONDS
        end

        timeout = Trading::RuntimeConfig.fetch_integer(
          "ai.ollama_timeout_seconds",
          default: DEFAULT_TIMEOUT_SECONDS,
          env_key: nil
        )
        timeout.positive? ? timeout : DEFAULT_TIMEOUT_SECONDS
      rescue ArgumentError, TypeError
        DEFAULT_TIMEOUT_SECONDS
      end

      def read_max_retries
        if (raw = ENV["OLLAMA_MAX_RETRIES"].to_s.strip).present?
          v = Integer(raw)
          return v.negative? ? 0 : v
        end

        retries = Trading::RuntimeConfig.fetch_integer("ai.ollama_max_retries", default: 2, env_key: nil)
        retries.negative? ? 0 : retries
      rescue ArgumentError, TypeError
        2
      end

      def read_api_key_string
        ENV["OLLAMA_API_KEY"].to_s.strip.presence ||
          Trading::RuntimeConfig.fetch_string("ai.ollama_api_key", default: "", env_key: nil).to_s.strip
      end
    end
  end
end
