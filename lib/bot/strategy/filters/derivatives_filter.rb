# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module DerivativesFilter
        def self.check(derivatives_data)
          return { passed: true, reason: "Derivatives unavailable — skipping gate" } if derivatives_data.nil?

          oi_trend        = derivatives_data[:oi_trend]
          funding_extreme = derivatives_data[:funding_extreme]
          funding_rate    = derivatives_data[:funding_rate]

          # Skip OI check if data not yet available
          if oi_trend == :falling
            return { passed: false, reason: "OI falling — potential divergence/trap, blocking entry" }
          end

          if funding_extreme
            return { passed: false, reason: "funding rate #{funding_rate} extreme — blocking entry" }
          end

          { passed: true, reason: "OI #{oi_trend || 'n/a'}, funding #{funding_rate&.round(5) || 'n/a'} within range" }
        end
      end
    end
  end
end
