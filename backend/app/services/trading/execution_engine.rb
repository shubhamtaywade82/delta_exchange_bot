# frozen_string_literal: true

module Trading
  class ExecutionEngine
    def self.execute(signal, session:, client:)
      new(signal, session, client).execute
    end

    def initialize(signal, session, client)
      @signal = signal
      @session = session
      @client = client
    end

    def execute
      idem_key = IdempotencyGuard.key(
        symbol: @signal.symbol,
        side: @signal.side,
        timestamp: @signal.candle_timestamp.to_i
      )

      unless IdempotencyGuard.acquire(idem_key)
        Rails.logger.warn("[ExecutionEngine] Duplicate signal skipped: #{idem_key}")
        return nil
      end

      RiskManager.validate!(@signal, session: @session)


      kill_signal = Trading::Risk::KillSwitch.call(portfolio: Trading::Risk::PortfolioSnapshot.current)
      if kill_signal == :halt_trading
        raise Trading::RiskManager::RiskError, "kill switch: trading halted"
      elsif kill_signal == :block_new_trades
        raise Trading::RiskManager::RiskError, "kill switch: exposure cap reached"
      end

      position = find_or_create_position!
      order_attrs = OrderBuilder.build(@signal, session: @session, position: position)
      order = OrdersRepository.create!(order_attrs)

      result = place_order(order)

      order.update!(
        exchange_order_id: result[:id]&.to_s,
        status: normalize_exchange_status(result[:status])
      )
      position.recalculate_from_orders!

      Rails.logger.info("[ExecutionEngine] Order placed: #{order.exchange_order_id} for #{@signal.symbol} #{@signal.side}")
      order
    rescue RiskManager::RiskError => e
      Rails.logger.warn("[ExecutionEngine] Risk rejected signal for #{@signal.symbol}: #{e.message}")
      raise
    rescue => e
      Rails.logger.error("[ExecutionEngine] Failed to execute signal for #{@signal.symbol}: #{e.message}")
      raise
    end

    private

    def place_order(order)
      return simulate_fill_at_market(order) if PaperTrading.enabled?

      @client.place_order(
        product_id: fetch_product_id(order.symbol),
        side: order.side,
        order_type: order.order_type,
        size: order.size,
        limit_price: order.price,
        client_order_id: order.client_order_id
      )
    end

    def simulate_fill_at_market(order)
      exchange_id  = "paper-#{SecureRandom.hex(8)}"
      fill_price   = synthetic_fill_price(order)
      fill_id      = "paper-fill:#{order.id}:#{exchange_id}:#{fill_price}:#{order.size}:#{Time.current.to_i}"

      FillProcessor.process(
        Events::OrderFilled.new(
          exchange_fill_id: fill_id,
          exchange_order_id: exchange_id,
          client_order_id: order.client_order_id,
          symbol: order.symbol,
          side: order.side,
          quantity: order.size,
          price: fill_price,
          fee: 0,
          filled_at: Time.current,
          status: "filled",
          raw_payload: { "source" => "paper_trading" }
        )
      )

      { id: exchange_id, status: "filled" }
    end

    def synthetic_fill_price(order)
      px = order.price.to_f
      return px if px.positive?

      mark = Rails.cache.read("ltp:#{order.symbol}")&.to_f
      raise "paper fill needs order price or cached ltp:#{order.symbol}" unless mark&.positive?

      mark
    end

    def find_or_create_position!
      Position.find_or_create_by!(symbol: @signal.symbol, side: @signal.side) do |position|
        position.status = "init"
      end
    end

    def fetch_product_id(symbol)
      Rails.cache.fetch("product_id:#{symbol}", expires_in: 1.hour) do
        config = SymbolConfig.find_by(symbol: symbol)
        raise "No product_id configured for #{symbol}" unless config&.respond_to?(:product_id)

        config.product_id
      end
    end

    def normalize_exchange_status(status)
      case status.to_s
      when "open", "submitted", "pending" then "submitted"
      when "partially_filled" then "partially_filled"
      when "filled" then "filled"
      when "cancelled", "canceled" then "cancelled"
      when "rejected" then "rejected"
      else "submitted"
      end
    end
  end
end
