# frozen_string_literal: true

module Trading
  module Strategy
    # Selector maps AI strategy label to deterministic strategy implementation.
    class Selector
      # @param ai_output [Hash]
      # @return [Class]
      def self.call(ai_output)
        case ai_output["strategy"]
        when "breakout" then Trading::Strategies::Breakout
        when "mean_reversion" then Trading::Strategies::MeanReversion
        else Trading::Strategies::Scalping
        end
      end
    end
  end
end
