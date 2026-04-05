# frozen_string_literal: true

module PaperTrading
  module Fees
    DEFAULT_MAKER_FEE_RATE = BigDecimal("0.0002")
    DEFAULT_TAKER_FEE_RATE = BigDecimal("0.0005")
    DEFAULT_GST_MULTIPLIER = BigDecimal("1.18")

    # When no +PaperProductSnapshot+ exists (e.g. Rails +Order+ path), use default fee rates from metadata.
    FeeProductStub = Struct.new(:raw_metadata, keyword_init: true)

    module_function

    def default_fee_product
      FeeProductStub.new(raw_metadata: {})
    end

    def taker_fee_rate_for_product(product)
      raw = product.raw_metadata&.dig("taker_fee_rate") || product.raw_metadata&.dig("taker_fee")
      v = raw&.to_d
      return DEFAULT_TAKER_FEE_RATE if v.nil? || !v.positive?

      v
    end

    def maker_fee_rate_for_product(product)
      raw = product.raw_metadata&.dig("maker_fee_rate") || product.raw_metadata&.dig("maker_fee")
      v = raw&.to_d
      return DEFAULT_MAKER_FEE_RATE if v.nil? || !v.positive?

      v
    end

    def effective_fee_rate(product:, liquidity:)
      base_rate = liquidity.to_s == "maker" ? maker_fee_rate_for_product(product) : taker_fee_rate_for_product(product)
      base_rate * gst_multiplier_for_product(product)
    end

    def gst_multiplier_for_product(product)
      raw = product.raw_metadata&.dig("gst_multiplier")
      value = raw&.to_d
      return DEFAULT_GST_MULTIPLIER if value.nil? || !value.positive?

      value
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
