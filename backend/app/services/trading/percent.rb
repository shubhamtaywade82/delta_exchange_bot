# frozen_string_literal: true

module Trading
  # Normalizes config/env percentage values to a fraction for internal math (0.015 = 1.5%).
  # Legacy keys store "percent points" (1.5 meaning 1.5%); values > 1 are divided by 100.
  # Values in (0, 1] are treated as already fractional (0.015 stays 0.015).
  module Percent
    module_function

    def as_fraction(value)
      f = Float(value)
      return f if f <= 1.0

      f / 100.0
    end
  end
end
