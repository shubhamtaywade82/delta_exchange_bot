# frozen_string_literal: true

module PaperTrading
  module Fees
    DEFAULT_TAKER_FEE_RATE = BigDecimal("0.0005")

    module_function

    def taker_fee_rate_for_product(product)
      raw = product.raw_metadata&.dig("taker_fee_rate") || product.raw_metadata&.dig("taker_fee")
      v = raw&.to_d
      return DEFAULT_TAKER_FEE_RATE if v.nil? || !v.positive?

      v
    end

    def notional_usd(quantity:, price:, contract_value:)
      quantity.to_d * contract_value.to_d * price.to_d
    end

    def fee_usd(notional_usd:, fee_rate:)
      notional_usd.to_d * fee_rate.to_d
    end

    def fee_inr(fee_usd:, usd_inr_rate:)
      (fee_usd.to_d * usd_inr_rate.to_d).round(2)
    end
  end
end
