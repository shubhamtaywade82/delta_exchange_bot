# frozen_string_literal: true

module Trading
  module Risk
    # PortfolioSnapshot derives open-book exposure and mark-to-market PnL from active positions.
    # +total_pnl+ is unrealized only; settled realized lives on +Trade+ rows and the portfolio ledger.
    class PortfolioSnapshot
      Result = Struct.new(:total_pnl, :total_exposure, keyword_init: true)

      # @return [Result]
      def self.current
        from_positions(Position.active)
      end

      # @param positions [Array<Position>, ActiveRecord::Relation]
      # @return [Result]
      def self.from_positions(positions)
        list = positions.respond_to?(:to_a) ? positions.to_a : Array(positions)

        total_unrealized = list.sum do |position|
          mark = Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
          PositionRisk.call(position: position, mark_price: mark).unrealized_pnl
        end

        total_exposure = list.sum do |position|
          mark = Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
          lots = position.size.to_d.abs
          lot = PositionLotSize.multiplier_for(position).to_d
          lots * lot * mark
        end

        Result.new(total_pnl: total_unrealized, total_exposure: total_exposure)
      end
    end
  end
end
