# frozen_string_literal: true

module Trading
  # Recalculates positions from fills and checks stored metrics vs canonical formulas.
  class PositionReconciliation
    TOLERANCE_USD = BigDecimal("0.05")

    class << self
      # Re-runs PositionRecalculator for every active row (heals drift vs fill ledger).
      def recalculate_all_active!
        count = 0
        Position.active.find_each do |position|
          PositionRecalculator.call(position.id)
          count += 1
        rescue StandardError => e
          HotPathErrorPolicy.log_swallowed_error(
            component: "PositionReconciliation",
            operation: "recalculate_all_active!",
            error:     e,
            log_level: :error,
            position_id: position.id
          )
        end
        Rails.logger.info("[PositionReconciliation] recalculated #{count} active positions")
        count
      end

      # Marks every active position dirty so the next ReconciliationJob run processes them.
      def mark_all_active_dirty!
        n = Position.active.update_all(needs_reconciliation: true)
        Rails.logger.info("[PositionReconciliation] marked #{n} active positions needs_reconciliation=true")
        n
      end

      # Compares stored margin / unrealized vs PositionRisk + margin formula at current mark.
      # @return [Array<Hash>] discrepancies (empty if all within tolerance)
      def verify_active_positions
        issues = []
        Position.active.find_each do |p|
          issues.concat(discrepancies_for(p))
        end
        issues
      end

      def log_verify_active!
        verify_active_positions.each do |row|
          Rails.logger.warn(
            "[PositionReconciliation] mismatch position_id=#{row[:position_id]} #{row[:field]} " \
            "expected=#{row[:expected]} stored=#{row[:stored]} symbol=#{row[:symbol]}"
          )
        end
      end

      private

      def discrepancies_for(p)
        out = []
        mark = Trading::MarkPrice.for_symbol(p.symbol)
        mark ||= Rails.cache.read("ltp:#{p.symbol}")&.to_d
        mark ||= p.entry_price&.to_d

        if mark.present? && p.entry_price.present? && p.size.to_d.positive?
          calc_unreal = Risk::PositionRisk.call(position: p, mark_price: mark).unrealized_pnl
          stored_unreal = p.unrealized_pnl_usd.to_d
          if (calc_unreal - stored_unreal).abs > TOLERANCE_USD
            out << {
              position_id: p.id,
              symbol: p.symbol,
              field: :unrealized_pnl_usd,
              expected: calc_unreal.to_f,
              stored: stored_unreal.to_f
            }
          end
        end

        lot = Risk::PositionLotSize.multiplier_for(p).to_d
        lev = p.leverage.to_d
        if lev.positive? && p.size.to_d.positive? && p.entry_price.present? && lot.positive?
          expected_margin = (p.size.to_d.abs * lot * p.entry_price.to_d.abs) / lev
          stored_margin = p.margin&.to_d || 0.to_d
          if (expected_margin - stored_margin).abs > TOLERANCE_USD
            out << {
              position_id: p.id,
              symbol: p.symbol,
              field: :margin,
              expected: expected_margin.to_f,
              stored: stored_margin.to_f
            }
          end
        end

        out
      end
    end
  end
end
