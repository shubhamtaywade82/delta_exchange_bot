# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Trading
  module Paper
    # Read-only risk-budget check before async ExecutionEngine for **live** +generated_signal+ paths
    # (+Trading::Paper::CapitalAllocator+ uses % of equity). Async +PaperTradingSignal+ jobs use
    # +PaperTrading::RrPositionSizer+ (+max_loss_inr+, no % capital risk).
    class SignalPreflight
      def self.call(generated_signal)
        portfolio = generated_signal.trading_session.portfolio
        equity = portfolio.equity
        risk_pct = generated_signal.risk_pct&.to_d&.nonzero? || BigDecimal("0.015")
        stop = generated_signal.stop_price&.to_d&.nonzero? || default_stop_price(generated_signal)
        unit = RiskUnitValue.for_symbol(generated_signal.symbol)

        CapitalAllocator.new(
          equity: equity,
          risk_pct: risk_pct,
          risk_unit_value: unit
        ).call(
          side: generated_signal.side,
          entry_price: generated_signal.entry_price,
          stop_price: stop
        )
      end

      def self.default_stop_price(signal)
        entry = signal.entry_price.to_d
        trail_pct = Trading::RuntimeConfig.fetch_float(
          "risk.trail_pct_for_sizing",
          default: 1.5,
          env_key: "RISK_TRAIL_PCT_FOR_SIZING"
        )
        trail_distance = entry * BigDecimal(trail_pct.to_s) / BigDecimal("100")

        case signal.side.to_s.downcase
        when "long", "buy"
          entry - trail_distance
        when "short", "sell"
          entry + trail_distance
        else
          entry - trail_distance
        end
      end
    end
  end
end
