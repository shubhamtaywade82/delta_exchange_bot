# frozen_string_literal: true

require "delta_exchange"

module Bot
  module Execution
    class OrderManager
      attr_reader :realized_pnl

      def initialize(config:, product_cache:, position_tracker:, risk_calculator:,
                     capital_manager:, logger:, notifier:, db_writer: nil)
        @config           = config
        @product_cache    = product_cache
        @position_tracker = position_tracker
        @risk_calculator  = risk_calculator
        @capital_manager  = capital_manager
        @logger           = logger
        @notifier         = notifier
        @db_writer        = db_writer
        @realized_pnl     = 0.0
      end

      def execute_signal(signal)
        symbol = signal.symbol

        if @position_tracker.open?(symbol)
          @logger.warn("skip_position_exists", symbol: symbol)
          return nil
        end

        leverage       = @config.leverage_for(symbol)
        available_usdt = @capital_manager.available_usdt
        contract_value = @product_cache.contract_value_for(symbol)

        lots = @risk_calculator.compute(
          available_usdt: available_usdt,
          entry_price_usd: signal.entry_price,
          leverage: leverage,
          risk_per_trade_pct: @config.risk_per_trade_pct,
          trail_pct: @config.trailing_stop_pct,
          contract_value: contract_value,
          max_margin_per_position_pct: @config.max_margin_per_position_pct
        )

        if lots.zero?
          @logger.warn("skip_insufficient_capital", symbol: symbol, available_usdt: available_usdt)
          return nil
        end

        fill_price     = place_order(symbol, signal.side, lots, signal)
        return nil unless fill_price

        @position_tracker.open(
          symbol:         symbol,
          side:           signal.side,
          lots:           lots,
          entry_price:    fill_price,
          leverage:       leverage,
          contract_value: contract_value,
          trail_pct:      @config.trailing_stop_pct
        )

        @db_writer&.record_opened(
          symbol:         symbol,
          side:           signal.side,
          lots:           lots,
          entry_price:    fill_price,
          leverage:       leverage,
          contract_value: contract_value,
          trail_pct:      @config.trailing_stop_pct
        )

        @logger.info("trade_opened", symbol: symbol, side: signal.side, entry_usd: fill_price,
                     lots: lots, leverage: leverage, mode: current_mode)
        @notifier.send_message(trade_opened_message(symbol, signal.side, fill_price, lots, leverage))
        fill_price
      rescue DeltaExchange::RateLimitError => e
        @logger.warn("rate_limited", symbol: symbol, retry_after: e.retry_after_seconds)
        sleep(e.retry_after_seconds)
        nil
      rescue DeltaExchange::ApiError => e
        @logger.error("order_failed", symbol: symbol, message: e.message)
        nil
      end

      def close_position(symbol, exit_price:, reason:)
        pos = @position_tracker.get(symbol)
        return unless pos

        unless @config.dry_run?
          begin
            place_close_order(symbol, pos[:side], pos[:lots])
          rescue DeltaExchange::RateLimitError => e
            @logger.warn("close_rate_limited", symbol: symbol, retry_after: e.retry_after_seconds)
            return nil
          rescue DeltaExchange::ApiError => e
            @logger.error("close_failed", symbol: symbol, message: e.message)
            return nil
          end
        end

        @position_tracker.close(symbol)

        pnl_usd       = calculate_pnl(pos, exit_price)
        @realized_pnl += pnl_usd
        duration       = (Time.now.utc - pos[:entry_time]).to_i
        pnl_inr        = (pnl_usd * @capital_manager.usd_to_inr_rate).round(2)

        @db_writer&.record_closed(
          symbol:           symbol,
          side:             pos[:side],
          lots:             pos[:lots],
          entry_price:      pos[:entry],
          exit_price:       exit_price,
          pnl_usd:          pnl_usd.round(4),
          pnl_inr:          pnl_inr,
          duration_seconds: duration
        )

        @logger.info("trade_closed", symbol: symbol, exit_usd: exit_price,
                     pnl_usd: pnl_usd.round(2), realized_pnl_usd: @realized_pnl.round(2),
                     reason: reason, duration_seconds: duration)
        @notifier.send_message(trade_closed_message(symbol, exit_price, pnl_usd, duration, reason))
      end

      private

      def place_order(symbol, side, lots, signal)
        return fake_fill(signal) if @config.dry_run?

        product_id = @product_cache.product_id_for(symbol)
        order = DeltaExchange::Models::Order.create(
          product_id: product_id,
          size: lots,
          side: side == :long ? "buy" : "sell",
          order_type: "market_order"
        )
        order.average_fill_price.to_f
      end

      def place_close_order(symbol, side, lots)
        product_id = @product_cache.product_id_for(symbol)
        DeltaExchange::Models::Order.create(
          product_id: product_id,
          size: lots,
          side: side == :long ? "sell" : "buy",
          order_type: "market_order"
        )
      end

      def fake_fill(signal)
        signal.entry_price.to_f
      end

      def calculate_pnl(pos, exit_price)
        lots           = pos[:lots]
        contract_value = @product_cache.contract_value_for(pos[:symbol])
        entry          = pos[:entry]  # stored as :entry by PositionTracker#open
        multiplier     = pos[:side] == :long ? 1 : -1
        multiplier * (exit_price - entry) * lots * contract_value
      end

      def current_mode
        return "dry_run"  if @config.dry_run?
        return "testnet"  if @config.testnet?
        "live"
      end

      def trade_opened_message(symbol, side, price, lots, leverage)
        emoji = side == :long ? "🟢" : "🔴"
        tag   = @config.dry_run? ? " [DRY RUN]" : ""
        stop  = side == :long ? price * (1 - @config.trailing_stop_pct / 100.0) : price * (1 + @config.trailing_stop_pct / 100.0)
        "#{emoji} #{side.to_s.upcase} #{symbol} opened#{tag}\nEntry: $#{format('%.2f', price)}\nLots: #{lots} | Leverage: #{leverage}x\nTrail Stop: $#{format('%.2f', stop)}"
      end

      def trade_closed_message(symbol, exit_price, pnl_usd, duration_secs, reason)
        hours   = duration_secs / 3600
        minutes = (duration_secs % 3600) / 60
        pnl_inr = (pnl_usd * @capital_manager.usd_to_inr_rate).round(0)
        sign    = pnl_usd >= 0 ? "+" : ""
        emoji   = pnl_usd >= 0 ? "🟢" : "🔴"
        "#{emoji} #{symbol} closed — #{reason}\nExit: $#{format('%.2f', exit_price)}\nPnL: #{sign}$#{format('%.2f', pnl_usd)} (#{sign}₹#{pnl_inr})\nDuration: #{hours}h #{minutes}m"
      end
    end
  end
end
