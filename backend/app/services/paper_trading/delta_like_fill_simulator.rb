# frozen_string_literal: true

module PaperTrading
  # Synthetic LTP-centered book, queue-style matching, and impact — shared by
  # +PaperTrading::ProcessSignalJob+ and (when enabled) +Trading::ExecutionEngine+ paper mode.
  class DeltaLikeFillSimulator
    FillSlice = Struct.new(:qty, :price, :liquidity, keyword_init: true)

    def self.plan_slices(ltp:, side:, order_type:, size:, limit_price: nil, spread_bps: nil, market_depth: nil)
      new(
        ltp: ltp.to_d,
        side: side.to_s,
        order_type: order_type.to_s,
        size: size,
        limit_price: limit_price,
        spread_bps: spread_bps,
        market_depth: market_depth
      ).plan_slices
    end

    def self.snapshot_hash(ltp:, spread_bps:, depth:)
      spread_multiplier = spread_bps / 10_000.to_d / 2.to_d
      ask = ltp * (1 + spread_multiplier)
      bid = ltp * (1 - spread_multiplier)
      { bids: [ [ bid, depth ] ], asks: [ [ ask, depth ] ] }
    end

    def initialize(ltp:, side:, order_type:, size:, limit_price: nil, spread_bps: nil, market_depth: nil)
      @ltp = ltp
      @side = side
      @order_type = order_type
      @size = size
      @limit_price = limit_price
      @spread_bps_override = spread_bps
      @market_depth_override = market_depth
    end

    def plan_slices
      depth = depth_value
      spread = spread_value
      book = OrderBook.new
      book.update!(self.class.snapshot_hash(ltp: @ltp, spread_bps: spread, depth: depth))
      engine = MatchingEngine.new(order_book: book)
      view = MatchingOrderView.new(
        order_type: @order_type,
        side: @side,
        size: @size,
        limit_price: limit_price_for_matching
      )
      raw = engine.execute(view)
      raw.map do |fill|
        adjusted = ImpactModel.apply(
          price: fill[:price],
          quantity: fill[:qty],
          depth: depth,
          side: @side
        )
        FillSlice.new(qty: fill[:qty], price: adjusted, liquidity: fill[:liquidity])
      end
    end

    private

    def limit_price_for_matching
      return nil if @limit_price.nil?

      d = @limit_price.to_d
      d.positive? ? d : nil
    end

    def depth_value
      return @market_depth_override.to_d unless @market_depth_override.nil?

      ENV.fetch("PAPER_MARKET_DEPTH", "100").to_d
    end

    def spread_value
      return @spread_bps_override.to_d unless @spread_bps_override.nil?

      ENV.fetch("PAPER_SPREAD_BPS", "0").to_d
    end
  end

  # Duck type for +MatchingEngine+ (+limit_price+, +order_type+, +side+, +size+).
  class MatchingOrderView
    attr_reader :order_type, :side, :size

    def initialize(order_type:, side:, size:, limit_price: nil)
      @order_type = order_type
      @side = side.to_s.downcase
      @size = size
      @limit_price = limit_price
    end

    def limit_price
      @limit_price
    end
  end
end
