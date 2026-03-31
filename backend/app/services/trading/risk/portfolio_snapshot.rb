# frozen_string_literal: true

module Trading
  module Risk
    # PortfolioSnapshot derives aggregate PnL and exposure from live positions and cached marks.
    class PortfolioSnapshot
      Result = Struct.new(:total_pnl, :total_exposure, keyword_init: true)

      # @return [Result]
      def self.current
        positions = Position.active

        total_unrealized = positions.sum do |position|
          mark = Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
          PositionRisk.call(position: position, mark_price: mark).unrealized_pnl
        end

        total_realized = positions.sum { |position| position.pnl_usd.to_d }
        total_exposure = positions.sum do |position|
          mark = Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
          lots = position.size.to_d.abs
          lot = PositionLotSize.multiplier_for(position).to_d
          lots * lot * mark
        end

        Result.new(total_pnl: total_realized + total_unrealized, total_exposure: total_exposure)
      end
    end
  end
end
