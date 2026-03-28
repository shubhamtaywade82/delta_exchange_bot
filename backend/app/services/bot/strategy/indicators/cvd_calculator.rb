# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module CVDCalculator
        def self.compute(trades)
          return { delta: 0, delta_trend: :neutral, delta_pct: 0 } if trades.nil? || trades.empty?

          buy_vol  = trades.select { |t| t[:side] == "buy"  || t["side"] == "buy" }.sum { |t| (t[:size] || t["size"]).to_f }
          sell_vol = trades.select { |t| t[:side] == "sell" || t["side"] == "sell" }.sum { |t| (t[:size] || t["size"]).to_f }
          
          total_vol = buy_vol + sell_vol
          return { delta: 0, delta_trend: :neutral, delta_pct: 0 } if total_vol.zero?

          delta     = buy_vol - sell_vol
          delta_pct = (delta / total_vol * 100.0).round(2)
          trend     = delta > 0 ? :bullish : :bearish

          {
            delta: delta.round(0),
            delta_trend: trend,
            delta_pct: delta_pct
          }
        end
      end
    end
  end
end
