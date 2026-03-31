# frozen_string_literal: true

module Finance
  # Risk-to-contracts sizing for Delta-style linear perps: contracts are integers;
  # risk per contract at stop = stop_distance × contract_value (quote impact per contract).
  class PositionSizer
    Result = Struct.new(
      :contracts,
      :risk_usd,
      :risk_per_contract,
      :stop_distance,
      keyword_init: true
    )

    class << self
      def compute!(balance_inr:, risk_percent:, entry_price:, stop_price:, contract_value:, usd_inr: nil)
        usd_inr = default_usd_inr if usd_inr.nil?

        raise ArgumentError, "invalid entry price" if entry_price.to_f <= 0
        raise ArgumentError, "invalid stop price" if stop_price.to_f <= 0
        raise ArgumentError, "contract_value must be > 0" if contract_value.to_f <= 0

        rate = usd_inr.to_f
        raise ArgumentError, "usd_inr must be > 0" if rate <= 0

        balance_usd = balance_inr.to_f / rate
        risk_usd = balance_usd * risk_percent.to_f

        stop_distance = (entry_price.to_f - stop_price.to_f).abs
        raise ArgumentError, "stop distance cannot be zero" if stop_distance.zero?

        risk_per_contract = stop_distance * contract_value.to_f
        contracts = (risk_usd / risk_per_contract).floor

        Result.new(
          contracts: [contracts, 0].max,
          risk_usd: risk_usd,
          risk_per_contract: risk_per_contract,
          stop_distance: stop_distance
        )
      end

      def default_usd_inr
        Setting.find_by(key: "usd_to_inr_rate")&.value&.to_f&.nonzero? || 85.0
      end
    end
  end
end
