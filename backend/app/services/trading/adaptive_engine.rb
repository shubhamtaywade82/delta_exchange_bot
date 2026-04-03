# frozen_string_literal: true

module Trading
  # AdaptiveEngine performs deterministic feature extraction + regime detection and AI meta-configuration.
  class AdaptiveEngine
    STRATEGIES = %w[scalping breakout mean_reversion].freeze

    # @param book [Trading::Orderbook::Book]
    # @param trades [Array<Hash, Fill>]
    # @return [Hash]
    def self.tick(book:, trades:, client: nil)
      features = Trading::Features::Extractor.call(book: book, trades: trades)
      regime = Trading::Strategy::RegimeDetector.call(features)

      cache_ttl = Trading::RuntimeConfig.fetch_integer("ai.config_cache_seconds", default: 10, env_key: "AI_CONFIG_CACHE_SECONDS")
      ai_config = Rails.cache.fetch("adaptive:ai_config:#{regime}", expires_in: cache_ttl.seconds) do
        Trading::Strategy::AiEdgeModel.call(features: features, regime: regime)
      end

      scores = STRATEGIES.index_with { |strategy| Trading::Learning::Metrics.score(strategy, regime) }
      selected_strategy = Trading::Learning::Explorer.choose(STRATEGIES, scores)
      strategy = Trading::Strategy::Selector.call("strategy" => selected_strategy)
      params = Trading::Learning::ParamProvider.fetch(strategy: selected_strategy, regime: regime)

      config = ai_config.merge(
        "aggression" => params.aggression.to_d,
        "risk_multiplier" => params.risk_multiplier.to_d,
        "bias" => params.bias.to_d,
        "expected_edge" => scores[selected_strategy].to_d
      )

      decision = strategy.call(book: book, features: features, config: config)

      {
        features: features,
        regime: regime,
        ai_config: ai_config,
        strategy: selected_strategy,
        decision: decision,
        expected_edge: scores[selected_strategy]
      }
    end
  end
end
