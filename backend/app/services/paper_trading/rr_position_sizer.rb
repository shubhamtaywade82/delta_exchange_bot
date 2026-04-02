# frozen_string_literal: true

module PaperTrading
  # Fixed max loss in INR at stop (not % of capital). Margin cap from available INR × leverage.
  class RrPositionSizer
    NO_CAP = (1 << 30)

    Result = Struct.new(
      :contracts,
      :qty_risk,
      :qty_margin,
      :final_contracts,
      :max_loss_inr,
      :risk_per_contract_usd,
      :stop_distance,
      :notional_usd,
      :required_margin_usd,
      keyword_init: true
    )

    class << self
      def compute!(
        max_loss_inr:,
        available_margin_inr:,
        usd_inr_rate:,
        entry_price:,
        stop_price:,
        contract_value:,
        leverage:,
        position_size_limit: nil
      )
        validate_prices!(entry_price, stop_price, contract_value)

        rate = usd_inr_rate.to_d
        raise ArgumentError, "usd_inr_rate must be positive" unless rate.positive?

        max_loss_usd = max_loss_inr.to_d / rate
        available_usd = available_margin_inr.to_d / rate

        stop_distance = (entry_price.to_d - stop_price.to_d).abs
        raise ArgumentError, "stop distance cannot be zero" if stop_distance.zero?

        cv = contract_value.to_d
        entry = entry_price.to_d
        risk_per_contract = stop_distance * cv
        qty_risk = (max_loss_usd / risk_per_contract).floor
        qty_risk = 0 if qty_risk.negative?

        lev = leverage_for_margin(leverage)
        qty_margin =
          if lev.positive? && available_usd.positive?
            num = available_usd * lev
            den = cv * entry
            den.positive? ? (num / den).floor : NO_CAP
          else
            NO_CAP
          end

        limit = position_size_limit&.to_i
        candidates = [ qty_risk, qty_margin ]
        candidates << limit if limit&.positive?
        final = candidates.min
        final = 0 if final.negative?

        notional_usd = final * cv * entry
        required_margin_usd = lev.positive? ? (notional_usd / lev) : notional_usd

        Result.new(
          contracts: final,
          qty_risk: qty_risk,
          qty_margin: qty_margin == NO_CAP ? 0 : qty_margin,
          final_contracts: final,
          max_loss_inr: max_loss_inr.to_d,
          risk_per_contract_usd: risk_per_contract,
          stop_distance: stop_distance,
          notional_usd: notional_usd,
          required_margin_usd: required_margin_usd
        )
      end

      private

      def validate_prices!(entry_price, stop_price, contract_value)
        raise ArgumentError, "invalid entry price" if entry_price.to_d <= 0
        raise ArgumentError, "invalid stop price" if stop_price.to_d <= 0
        raise ArgumentError, "contract_value must be > 0" if contract_value.to_d <= 0
      end

      def leverage_for_margin(leverage)
        v = leverage.to_i
        v.positive? ? v : 1
      end
    end
  end
end
