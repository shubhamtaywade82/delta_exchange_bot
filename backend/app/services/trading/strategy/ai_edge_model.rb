# frozen_string_literal: true

require "digest"
require "json"

module Trading
  module Strategy
    # AiEdgeModel uses Ollama for meta-configuration (strategy/risk tuning), never direct trade signals.
    class AiEdgeModel
      CACHE_TTL = ENV.fetch("AI_CONFIG_CACHE_SECONDS", 10).to_i

      # @param features [Hash]
      # @param regime [Symbol]
      # @return [Hash]
      def self.call(features:, regime:)
        Rails.cache.fetch(cache_key(features, regime), expires_in: CACHE_TTL.seconds) do
          response = Ai::OllamaClient.ask(prompt(features: features, regime: regime))
          normalized = normalize_response(parse_response(response))
          audit!(features: features, regime: regime, response: normalized)
          normalized
        end
      rescue StandardError => e
        Rails.logger.warn("[AiEdgeModel] fallback due to #{e.class}: #{e.message}")
        fallback
      end

      def self.fallback
        { "strategy" => "scalping", "risk_multiplier" => 1.0, "aggression" => 0.5 }
      end

      def self.parse_response(response)
        JSON.parse(response)
      rescue JSON::ParserError
        json_fragment = response.to_s[/\{.*\}/m]
        raise unless json_fragment

        JSON.parse(json_fragment)
      end

      def self.normalize_response(response)
        strategy = normalize_strategy(response["strategy"])
        {
          "strategy" => strategy,
          "risk_multiplier" => clamp_float(response["risk_multiplier"], 0.5, 2.0, fallback["risk_multiplier"]),
          "aggression" => clamp_float(response["aggression"], 0.0, 1.0, fallback["aggression"])
        }
      end

      def self.normalize_strategy(value)
        allowed = %w[scalping breakout mean_reversion]
        strategy = value.to_s
        allowed.include?(strategy) ? strategy : fallback["strategy"]
      end

      def self.clamp_float(value, min, max, default)
        numeric = Float(value)
        [[numeric, max].min, min].max
      rescue ArgumentError, TypeError
        default
      end

      def self.prompt(features:, regime:)
        <<~PROMPT
          You are a trading optimizer for derivatives execution.
          Input regime=#{regime}
          spread=#{features[:spread]}
          imbalance=#{features[:imbalance]}
          volatility=#{features[:volatility]}
          momentum=#{features[:momentum]}

          Output JSON only with keys:
          strategy: scalping|breakout|mean_reversion
          risk_multiplier: float (0.5-2.0)
          aggression: float (0-1)
        PROMPT
      end

      def self.cache_key(features, regime)
        digest = Digest::SHA256.hexdigest(features.sort.to_h.to_json)
        "ai:edge:#{regime}:#{digest}"
      end

      def self.audit!(features:, regime:, response:)
        Rails.logger.info("[AiEdgeModel] regime=#{regime} features=#{features.to_json} response=#{response.to_json}")
      end
    end
  end
end
