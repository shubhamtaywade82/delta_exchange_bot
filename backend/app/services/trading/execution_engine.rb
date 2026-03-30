# frozen_string_literal: true

module Trading
  class ExecutionEngine
    def self.execute(signal, session:, client:)
      new(signal, session, client).execute
    end

    def initialize(signal, session, client)
      @signal  = signal
      @session = session
      @client  = client
    end

    def execute
      idem_key = IdempotencyGuard.key(
        symbol:    @signal.symbol,
        side:      @signal.side,
        timestamp: @signal.candle_timestamp.to_i
      )

      unless IdempotencyGuard.acquire(idem_key)
        Rails.logger.warn("[ExecutionEngine] Duplicate signal skipped: #{idem_key}")
        return nil
      end

      RiskManager.validate!(@signal, session: @session)

      order_attrs = OrderBuilder.build(@signal, session: @session)
      order       = OrdersRepository.create!(order_attrs)

      result = place_order(order)

      order.update!(
        exchange_order_id: result[:id]&.to_s,
        status:            result[:status] || "open"
      )

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
      @client.place_order(
        product_id:  fetch_product_id(order.symbol),
        side:        order.side,
        order_type:  order.order_type,
        size:        order.size,
        limit_price: order.price
      )
    end

    def fetch_product_id(symbol)
      Rails.cache.fetch("product_id:#{symbol}", expires_in: 1.hour) do
        config = SymbolConfig.find_by(symbol: symbol)
        raise "No product_id configured for #{symbol}" unless config&.respond_to?(:product_id)

        config.product_id
      end
    end
  end
end
