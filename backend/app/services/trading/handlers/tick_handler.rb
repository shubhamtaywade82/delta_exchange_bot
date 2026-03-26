# frozen_string_literal: true

module Trading
  module Handlers
    class TickHandler
      def initialize(candle, session, client)
        @candle  = candle
        @session = session
        @client  = client
      end

      def call
        return unless @candle.closed

        signal = evaluate_strategy
        return unless signal

        converted = Events::SignalGenerated.new(
          symbol:           signal.symbol,
          side:             signal.side,
          entry_price:      signal.entry_price,
          candle_timestamp: signal.candle_ts,
          strategy:         @session.strategy,
          session_id:       @session.id
        )

        EventBus.publish(:signal_generated, converted)
        ExecutionEngine.execute(converted, session: @session, client: @client)
      rescue RiskManager::RiskError => e
        Rails.logger.warn("[TickHandler] Risk blocked signal for #{@candle.symbol}: #{e.message}")
      rescue => e
        Rails.logger.error("[TickHandler] Error processing candle for #{@candle.symbol}: #{e.message}")
      end

      private

      def evaluate_strategy
        config   = Bot::Config.load
        strategy = Bot::Strategy::MultiTimeframe.new(
          client:    @client,
          config:    config,
          symbols:   [@candle.symbol],
          logger:    Rails.logger,
          notifier:  nil
        )
        strategy.evaluate(@candle.symbol)
      rescue => e
        Rails.logger.error("[TickHandler] Strategy evaluation failed for #{@candle.symbol}: #{e.message}")
        nil
      end
    end
  end
end
