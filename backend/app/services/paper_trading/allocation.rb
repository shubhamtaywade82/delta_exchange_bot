# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  Allocation = Struct.new(
    :quantity,
    :risk_budget,
    :per_unit_risk,
    :notional,
    :target_price,
    :stop_price,
    :rr,
    keyword_init: true
  ) do
    def valid?
      quantity.to_i.positive?
    end
  end
end
