# frozen_string_literal: true

module PaperTrading
  # Applies one order fill to paper positions + INR ledger.
  class FillApplier
    def initialize(order:, wallet:, product:)
      @order = order
      @wallet = wallet
      @product = product
    end

    # @param price [BigDecimal, String, Numeric] fill price in USD
    # @param size [Integer] number of contracts
    # @param leverage [Integer, nil] leverage override
    # @param liquidity [String, Symbol] maker or taker
    # @param market_snapshot [Hash] optional { bid:, ask:, depth: }
    def call(price:, size:, leverage: nil, liquidity: :taker, market_snapshot: {})
      execution_price = compute_execution_price(price:, size:, liquidity:, market_snapshot:)
      maybe_apply_execution_delay!
      fill = create_fill!(price: execution_price, size: size, liquidity: liquidity)

      PositionManager.new(wallet: @wallet, product: @product).apply_fill(
        fill: fill,
        fill_side: @order.side,
        quantity: size,
        price: execution_price,
        leverage: leverage
      )
    end

    private

    def create_fill!(price:, size:, liquidity:)
      normalized_size = Integer(size)
      @order.paper_fills.create!(
        size: normalized_size,
        filled_qty: normalized_size,
        closed_qty: 0,
        margin_inr_per_fill: 0,
        liquidity: liquidity.to_s,
        price: price.to_d,
        filled_at: Time.current
      )
    end

    def compute_execution_price(price:, size:, liquidity:, market_snapshot:)
      base_price = price.to_d
      bid = market_snapshot[:bid]&.to_d
      ask = market_snapshot[:ask]&.to_d
      depth = market_snapshot[:depth]&.to_d
      side = @order.side.to_s.downcase

      return maker_price(base_price:, bid:, ask:, side:) if liquidity.to_s == "maker"

      taker_base = taker_price(base_price:, bid:, ask:, side:)
      apply_slippage(base_price: taker_base, size: size.to_d, depth: depth, side: side)
    end

    def maker_price(base_price:, bid:, ask:, side:)
      return bid if side == "buy" && bid&.positive?
      return ask if side == "sell" && ask&.positive?

      base_price
    end

    def taker_price(base_price:, bid:, ask:, side:)
      return ask if side == "buy" && ask&.positive?
      return bid if side == "sell" && bid&.positive?

      spread_bps = ENV["PAPER_SPREAD_BPS"]&.to_d || 0.to_d
      volatility_factor = ENV["PAPER_VOLATILITY_FACTOR"]&.to_d || 0.to_d
      spread_multiplier = (spread_bps / 10_000.to_d / 2.to_d) * (1 + volatility_factor)
      side == "buy" ? base_price * (1 + spread_multiplier) : base_price * (1 - spread_multiplier)
    end

    def apply_slippage(base_price:, size:, depth:, side:)
      base_slippage_bps = ENV["PAPER_SLIPPAGE_BPS"]&.to_d || 0.to_d
      impact_coeff_bps = ENV["PAPER_IMPACT_BPS"]&.to_d || 0.to_d
      market_depth = depth&.positive? ? depth : (ENV["PAPER_DEFAULT_DEPTH"]&.to_d || size)
      impact_ratio = market_depth.positive? ? (size / market_depth) : 0.to_d
      impact = impact_coeff_bps * impact_ratio**BigDecimal("1.5")
      max_slippage_bps = ENV["PAPER_MAX_SLIPPAGE_BPS"]&.to_d
      total_bps = base_slippage_bps + impact
      total_bps = [ total_bps, max_slippage_bps ].min if max_slippage_bps&.positive?
      slippage_multiplier = total_bps / 10_000.to_d

      side == "buy" ? base_price * (1 + slippage_multiplier) : base_price * (1 - slippage_multiplier)
    end

    def maybe_apply_execution_delay!
      mean_ms = ENV["PAPER_EXEC_DELAY_MS"]&.to_f.to_f
      return if mean_ms <= 0

      std_ms = ENV["PAPER_EXEC_DELAY_STD_MS"]&.to_f.to_f
      sample_ms = if std_ms.positive?
        gaussian_sample(mean: mean_ms, stddev: std_ms)
      else
        mean_ms
      end

      sleep([ sample_ms, 0 ].max / 1000.0)
    end

    def gaussian_sample(mean:, stddev:)
      u1 = [ rand, Float::MIN ].max
      u2 = rand
      z0 = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
      mean + (z0 * stddev)
    end
  end
end
