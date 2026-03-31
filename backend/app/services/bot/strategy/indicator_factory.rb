# frozen_string_literal: true

require_relative "supertrend"
require_relative "ml_adaptive_supertrend"

module Bot
  module Strategy
    # Dispatches indicator computation from config (mirrors algo_scalper_api IndicatorFactory keys).
    module IndicatorFactory
      module_function

      CLASSIC_TYPES = %w[supertrend st classic].freeze
      ML_TYPES      = %w[ml_adaptive_supertrend mast ml_st ml_adaptive].freeze

      def supertrend_kind(config)
        kind = normalize_supertrend_type(config.supertrend_indicator_type)
        return :ml_adaptive if kind == :ml_adaptive
        return :ml_adaptive if config.supertrend_variant == "ml_adaptive"

        :classic
      end

      def compute_supertrend(candles, config:)
        case supertrend_kind(config)
        when :ml_adaptive
          MlAdaptiveSupertrend.compute(
            candles,
            atr_len: config.supertrend_atr_period,
            factor: config.supertrend_multiplier,
            training_period: config.ml_adaptive_supertrend_training_period,
            highvol: config.ml_adaptive_supertrend_highvol,
            midvol: config.ml_adaptive_supertrend_midvol,
            lowvol: config.ml_adaptive_supertrend_lowvol
          )
        else
          Supertrend.compute(
            candles,
            atr_period: config.supertrend_atr_period,
            multiplier: config.supertrend_multiplier
          )
        end
      end

      # @param type [String] indicator type string (e.g. from external configs)
      # @return [Symbol] :classic or :ml_adaptive
      def normalize_supertrend_type(type)
        t = type.to_s.downcase.strip
        return :ml_adaptive if ML_TYPES.include?(t)
        return :classic if t.empty? || CLASSIC_TYPES.include?(t)

        :classic
      end
    end
  end
end
