# frozen_string_literal: true

module Trading
  class ExecutionEngine
    def self.execute(signal, session:, client:)
      new(signal, session, client).execute
    end

    def self.canonical_position_side(raw)
      case raw.to_s.downcase
      when "long", "buy" then "long"
      when "short", "sell" then "short"
      else raw.to_s
      end
    end

    # Matches legacy rows stored as buy/sell as well as long/short.
    def self.active_position_side_keys(raw)
      case canonical_position_side(raw)
      when "long" then %w[long buy]
      when "short" then %w[short sell]
      else [raw.to_s]
      end
    end

    def initialize(signal, session, client)
      @signal = signal
      @session = session
      @client = client
    end

    def execute
      idem_key = IdempotencyGuard.key_for_signal(@signal)
      return nil unless acquire_idempotency!(idem_key)

      order_persisted = false
      ensure_session_has_portfolio!

      validate_risk_and_portfolio_guard!

      position = find_or_create_position!
      order_attrs = OrderBuilder.build(@signal, session: @session, position: position)
      validate_margin_affordability!(order_attrs, position)
      order = OrdersRepository.create!(order_attrs)
      order_persisted = true

      result = place_order(order)
      persist_order_result!(order, result)
      position.recalculate_from_orders!

      Rails.logger.info("[ExecutionEngine] Order placed: #{order.exchange_order_id} for #{@signal.symbol} #{@signal.side}")
      order
    rescue OrderBuilder::SizingError => e
      release_idempotency!(idem_key)
      Rails.logger.warn("[ExecutionEngine] Sizing rejected signal for #{@signal.symbol}: #{e.message}")
      raise RiskManager::RiskError, e.message
    rescue RiskManager::RiskError => e
      release_idempotency!(idem_key)
      Rails.logger.warn("[ExecutionEngine] Risk rejected signal for #{@signal.symbol}: #{e.message}")
      raise
    rescue StandardError => e
      release_idempotency!(idem_key) unless order_persisted
      HotPathErrorPolicy.log_swallowed_error(
        component: "ExecutionEngine",
        operation: "execute",
        error:     e,
        report_handled: false,
        symbol:    @signal&.symbol,
        session_id: @session&.id,
        order_persisted: order_persisted
      )
      raise
    end

    private

    def acquire_idempotency!(idem_key)
      return true if IdempotencyGuard.acquire(idem_key)

      Rails.logger.warn("[ExecutionEngine] Duplicate signal skipped: #{idem_key}")
      false
    end

    def release_idempotency!(idem_key)
      IdempotencyGuard.release(idem_key)
    end

    def ensure_session_has_portfolio!
      return if @session.portfolio_id.present?

      @session.save!
      @session.reload
    end

    def validate_margin_affordability!(order_attrs, position)
      if PaperTrading.enabled?
        return if PaperRiskOverride.active?
      elsif !live_margin_affordability_enabled?
        return
      end

      fill_price = resolve_intended_fill_price(order_attrs)
      Trading::Risk::MarginAffordability.verify!(
        portfolio: @session.portfolio,
        symbol: order_attrs[:symbol].to_s,
        order_side: order_attrs[:side].to_s,
        order_size: order_attrs[:size],
        fill_price: fill_price,
        position: position,
        session: @session
      )
    end

    def live_margin_affordability_enabled?
      Trading::RuntimeConfig.fetch_boolean(
        "risk.live_margin_affordability_enabled",
        default: false,
        env_key: "RISK_LIVE_MARGIN_AFFORDABILITY_ENABLED"
      )
    end

    def resolve_intended_fill_price(order_attrs)
      px = decimal_price(order_attrs[:price])
      return px if px.positive?

      mark = decimal_price(Rails.cache.read("ltp:#{order_attrs[:symbol]}"))
      unless mark&.positive?
        raise RiskManager::RiskError, "execution needs order price or cached ltp:#{order_attrs[:symbol]}"
      end

      mark
    end

    def validate_risk_and_portfolio_guard!
      RiskManager.validate!(@signal, session: @session)

      return if PaperTrading.enabled? && PaperRiskOverride.active?

      guard_state = Trading::Risk::PortfolioGuard.call(portfolio: Trading::Risk::PortfolioSnapshot.current)
      if guard_state == :halt_trading
        raise Trading::RiskManager::RiskError, "portfolio guard: trading halted"
      elsif guard_state == :block_new_trades
        raise Trading::RiskManager::RiskError, "portfolio guard: exposure cap reached"
      end
    end

    def persist_order_result!(order, result)
      order.update!(
        exchange_order_id: result[:id]&.to_s,
        status: normalize_exchange_status(result[:status])
      )
    end

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
      px = decimal_price(order.price)
      return px if px.positive?

      mark = decimal_price(Rails.cache.read("ltp:#{order.symbol}"))
      raise "paper fill needs order price or cached ltp:#{order.symbol}" unless mark&.positive?

      mark
    end

    def find_or_create_position!
      symbol = @signal.symbol.to_s
      side = self.class.canonical_position_side(@signal.side)
      contract_scalar = Trading::Risk::PositionLotSize.from_exchange(symbol)
      leverage = @session.leverage.to_i
      leverage = 10 if leverage.zero?
      product_id = fetch_product_id(symbol)

      position = Position.where(portfolio_id: @session.portfolio_id, symbol: symbol)
                         .where(status: Position::NET_OPEN_STATUSES)
                         .first

      if position
        updates = {}
        updates[:leverage] = leverage if position.leverage.blank? || position.leverage.to_i.zero?
        updates[:product_id] = product_id if position.product_id.blank?
        if contract_scalar.to_f.positive? && (position.contract_value.blank? || position.contract_value.to_f.zero?)
          updates[:contract_value] = contract_scalar
        end
        updates[:side] = side if position.side.to_s != side
        position.update!(updates) if updates.any?
        return position
      end

      position = Position.new(
        portfolio: @session.portfolio,
        symbol: symbol,
        side: side
      )
      position.status = "init"
      position.leverage = leverage
      position.product_id = product_id
      position.contract_value = contract_scalar if contract_scalar.to_f.positive?
      position.save!
      position
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

    def decimal_price(value)
      return BigDecimal("0") if value.respond_to?(:blank?) ? value.blank? : value.nil?

      value.to_d
    rescue ArgumentError, TypeError
      BigDecimal("0")
    end
  end
end
