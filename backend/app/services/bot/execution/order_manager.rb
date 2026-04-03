# frozen_string_literal: true


module Bot
  module Execution
    class OrderManager
      CATEGORY_BY_BROKER_CODE = {
        "ip_not_whitelisted_for_api_key" => "auth_whitelist",
        "expired_signature" => "signature_time_skew"
      }.freeze

      attr_reader :realized_pnl

      def initialize(config:, product_cache:, position_tracker:, risk_calculator:,
                     capital_manager:, price_store:, logger:, notifier:)
        @config           = config
        @product_cache    = product_cache
        @position_tracker = position_tracker
        @risk_calculator  = risk_calculator
        @capital_manager  = capital_manager
        @price_store      = price_store
        @logger           = logger
        @notifier         = notifier
        @realized_pnl     = 0.0
      end

      def execute_signal(signal)
        symbol = signal.symbol
        signal_id = signal.respond_to?(:signal_id) ? signal.signal_id : nil
        @logger.info("order_attempted", signal_id: signal_id, symbol: symbol, side: signal.side, entry_price: signal.entry_price)

        if @position_tracker.open?(symbol)
          @logger.warn("skip_position_exists", symbol: symbol)
          return nil
        end

        leverage        = @config.leverage_for(symbol)
        snapshot        = @position_tracker.snapshot(@price_store.all)
        available_usdt  = @capital_manager.spendable_usdt(
          blocked_margin: snapshot[:blocked_margin],
          unrealized_pnl: snapshot[:unrealized_pnl]
        )
        contract_value  = @product_cache.contract_value_for(symbol)

        lots = @risk_calculator.compute(
          available_usdt: available_usdt,
          entry_price_usd: signal.entry_price,
          leverage: leverage,
          risk_per_trade_pct: @config.risk_per_trade_pct,
          trail_pct: @config.trailing_stop_pct,
          contract_value: contract_value,
          max_margin_per_position_pct: @config.max_margin_per_position_pct,
          side: signal.side
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
          trail_pct:      @config.trailing_stop_pct,
          product_id:     @product_cache.product_id_for(symbol)
        )

        @logger.info("trade_opened", symbol: symbol, side: signal.side, entry_usd: fill_price,
                     lots: lots, leverage: leverage, mode: current_mode)
        @notifier.notify_trade_opened(
          symbol: symbol,
          side: signal.side,
          price: fill_price,
          lots: lots,
          added_lots: lots,
          leverage: leverage,
          trailing_stop: trail_stop_price(signal.side, fill_price),
          mode: current_mode
        )
        fill_price
      rescue DeltaExchange::RateLimitError => e
        capture_incident(
          kind: "order_failed",
          category: "rate_limit",
          symbol: symbol,
          signal: signal,
          message: e.message
        )
        @logger.warn("rate_limited", signal_id: signal_id, symbol: symbol, retry_after: e.retry_after_seconds)
        sleep(e.retry_after_seconds)
        nil
      rescue DeltaExchange::ApiError => e
        category, broker_code = classify_api_error(e.message)
        capture_incident(
          kind: "order_failed",
          category: category,
          symbol: symbol,
          signal: signal,
          message: e.message,
          details: { broker_code: broker_code }
        )
        @logger.error("order_failed", signal_id: signal_id, symbol: symbol, category: category, broker_code: broker_code, message: e.message)
        nil
      end

      def close_position(symbol, exit_price:, reason:)
        pos = @position_tracker.get(symbol)
        return unless pos

        if @config.live?
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

        pnl_usd       = calculate_pnl(pos, exit_price)
        pnl_inr       = (pnl_usd * @capital_manager.usd_to_inr_rate).round(2)
        @realized_pnl += pnl_usd
        duration       = (Time.now.utc - pos[:entry_time]).to_i

        @position_tracker.close(symbol, exit_price: exit_price, pnl_usd: pnl_usd, pnl_inr: pnl_inr)

        Trade.create!(
          symbol:           symbol,
          side:             pos[:side].to_s,
          entry_price:      pos[:entry],
          exit_price:       exit_price,
          size:             pos[:lots],
          pnl_usd:          pnl_usd,
          pnl_inr:          pnl_inr,
          duration_seconds: duration,
          closed_at:        Time.now.utc,
          regime:           ENV.fetch("BOT_TRADE_REGIME", "unknown"),
          strategy:         ENV.fetch("BOT_TRADE_STRATEGY", "multi_timeframe")
        )

        @logger.info("trade_closed", symbol: symbol, exit_usd: exit_price,
                     pnl_usd: pnl_usd.round(2), realized_pnl_usd: @realized_pnl.round(2),
                     reason: reason, duration_seconds: duration)
        @notifier.notify_trade_closed(
          symbol: symbol,
          exit_price: exit_price,
          pnl_usd: pnl_usd,
          pnl_inr: pnl_inr,
          duration_seconds: duration,
          reason: reason
        )
      end

      private

      def place_order(symbol, side, lots, signal)
        return fake_fill(signal) unless @config.live?

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
        return if !@config.live?

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

      def trail_stop_price(side, entry_price)
        if side == :long
          entry_price * (1 - @config.trailing_stop_pct / 100.0)
        else
          entry_price * (1 + @config.trailing_stop_pct / 100.0)
        end
      end

      def classify_api_error(message)
        broker_code = message.to_s[/\"code\"=>\"([^\"]+)\"/, 1]
        category = CATEGORY_BY_BROKER_CODE.fetch(broker_code, "unknown")
        [category, broker_code]
      end

      def capture_incident(kind:, category:, symbol:, signal:, message:, details: {})
        signal_id = signal.respond_to?(:signal_id) ? signal.signal_id : nil
        IncidentStore.record!(
          kind: kind,
          category: category,
          message: message,
          symbol: symbol,
          signal_id: signal_id,
          details: details
        )
      end
    end
  end
end
