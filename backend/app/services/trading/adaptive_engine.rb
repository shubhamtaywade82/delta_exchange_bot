# frozen_string_literal: true

module Trading
  # AdaptiveEngine performs deterministic feature extraction + regime detection and AI meta-configuration.
  class AdaptiveEngine
    STRATEGIES = %w[scalping breakout mean_reversion].freeze

    # @param book [Trading::Orderbook::Book]
    # @param trades [Array<Hash, Fill>]
    # @param client [Object]
    # @return [Hash]
    def self.tick(book:, trades:, client:)
      features = Trading::Features::Extractor.call(book: book, trades: trades)
      regime = Trading::Strategy::RegimeDetector.call(features)

      ai_config = Rails.cache.fetch("adaptive:ai_config:#{regime}", expires_in: ENV.fetch("AI_CONFIG_CACHE_SECONDS", 10).to_i.seconds) do
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
      route_decision(decision: decision, book: book, client: client)

      {
        features: features,
        regime: regime,
        ai_config: ai_config,
        strategy: selected_strategy,
        decision: decision,
        expected_edge: scores[selected_strategy]
      }
    end

    def self.route_decision(decision:, book:, client:)
      qty = ENV.fetch("MICROSTRUCTURE_ORDER_QTY", "1").to_d

      case decision
      when :buy
        Trading::Execution::OrderRouter.place!(decision: :maker_buy, book: book, qty: qty, client: client)
      when :sell
        Trading::Execution::OrderRouter.place!(decision: :maker_sell, book: book, qty: qty, client: client)
      else
        nil
      end
    end
  end
end
