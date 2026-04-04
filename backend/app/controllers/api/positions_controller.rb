class Api::PositionsController < ApplicationController
  def index
    prices = Bot::Feed::PriceStore.new.all
    positions = Position.active.map do |pos|
      ltp = prices[pos.symbol]

      pos.as_json.merge(
        ltp: ltp,
        unrealized_pnl: calculate_unrealized_pnl(pos, ltp)
      )
    end

    render json: positions
  end

  private

  def calculate_unrealized_pnl(pos, ltp)
    return 0.0 unless ltp
    multiplier = pos.side == "long" ? 1 : -1
    (ltp - pos.entry_price.to_f) * pos.size.to_f * pos.contract_value.to_f * multiplier
  end
end
