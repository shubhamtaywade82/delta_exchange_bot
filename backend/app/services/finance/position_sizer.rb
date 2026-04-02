# frozen_string_literal: true

module Finance
  # Risk-to-contracts sizing for Delta-style linear perps: contracts are integers;
  # risk per contract at stop = stop_distance × contract_value (quote impact per contract).
  # Optional margin cap: floor((margin_wallet_usd × fee_buffer × leverage) / (contract_value × entry_price)).
  class PositionSizer
    DEFAULT_FEE_BUFFER = 0.98
    NO_MARGIN_CAP = (1 << 30)

    Result = Struct.new(
      :contracts,
      :qty_risk,
      :qty_margin,
      :final_contracts,
      :risk_usd,
      :risk_per_contract,
      :stop_distance,
      :notional_usd,
      :required_margin_usd,
      :required_margin_inr,
      keyword_init: true
    )

    class << self
      def compute!(balance_inr:, risk_percent:, entry_price:, stop_price:, contract_value:, usd_inr: nil,
                   leverage: nil, fee_buffer: nil, position_size_limit: nil, margin_wallet_usd: nil)
        usd_inr = default_usd_inr if usd_inr.nil?
        buffer = normalize_fee_buffer(fee_buffer)

        validate_prices!(entry_price, stop_price, contract_value, usd_inr)

        balance_usd = balance_inr.to_f / usd_inr.to_f
        risk_usd = balance_usd * risk_percent.to_f

        stop_distance = (entry_price.to_f - stop_price.to_f).abs
        raise ArgumentError, "stop distance cannot be zero" if stop_distance.zero?

        cv = contract_value.to_f
        entry = entry_price.to_f
        risk_per_contract = stop_distance * cv
        qty_risk = (risk_usd / risk_per_contract).floor
        qty_risk = 0 if qty_risk.negative?

        qty_margin = compute_qty_margin(
          margin_wallet_usd: margin_wallet_usd,
          balance_usd: balance_usd,
          leverage: leverage,
          fee_buffer: buffer,
          contract_value: cv,
          entry_price: entry
        )

        limit = position_size_limit&.to_i
        candidates = [ qty_risk, qty_margin ]
        candidates << limit if limit&.positive?
        final_contracts = candidates.min
        final_contracts = 0 if final_contracts.negative?

        lev = leverage_for_margin(leverage)
        notional_usd = final_contracts * cv * entry
        required_margin_usd = lev.positive? ? (notional_usd / lev) : notional_usd
        required_margin_inr = required_margin_usd * usd_inr.to_f

        Result.new(
          contracts: final_contracts,
          qty_risk: qty_risk,
          qty_margin: qty_margin,
          final_contracts: final_contracts,
          risk_usd: risk_usd,
          risk_per_contract: risk_per_contract,
          stop_distance: stop_distance,
          notional_usd: notional_usd,
          required_margin_usd: required_margin_usd,
          required_margin_inr: required_margin_inr
        )
      end

      def default_usd_inr
        Finance::UsdInrRate.current
      end

      private

      def validate_prices!(entry_price, stop_price, contract_value, usd_inr)
        raise ArgumentError, "invalid entry price" if entry_price.to_f <= 0
        raise ArgumentError, "invalid stop price" if stop_price.to_f <= 0
        raise ArgumentError, "contract_value must be > 0" if contract_value.to_f <= 0
        raise ArgumentError, "usd_inr must be > 0" if usd_inr.to_f <= 0
      end

      def normalize_fee_buffer(fee_buffer)
        b = fee_buffer.nil? ? DEFAULT_FEE_BUFFER : fee_buffer.to_f
        raise ArgumentError, "fee_buffer must be in (0, 1]" unless b.positive? && b <= 1.0

        b
      end

      def compute_qty_margin(margin_wallet_usd:, balance_usd:, leverage:, fee_buffer:, contract_value:, entry_price:)
        lev = leverage_for_margin(leverage)
        return NO_MARGIN_CAP if lev <= 0

        wallet = margin_wallet_usd.nil? ? balance_usd : margin_wallet_usd.to_f
        return NO_MARGIN_CAP unless wallet.positive?

        num = wallet * fee_buffer * lev
        den = contract_value * entry_price
        return NO_MARGIN_CAP if den <= 0

        (num / den).floor
      end

      def leverage_for_margin(leverage)
        lev = leverage.to_f
        lev.positive? ? lev : 0.0
      end
    end
  end
end
