# frozen_string_literal: true

module Trading
  # Logs and reports errors on loops that must continue (shutdown, per-order cancel, fill handling).
  module HotPathErrorPolicy
    class << self
      def log_swallowed_error(component:, operation:, error:, **context)
        ctx = context.compact
        suffix = ctx.empty? ? "" : " #{ctx.map { |k, v| "#{k}=#{v}" }.join(' ')}"
        Rails.logger.error("[#{component}] #{operation} — #{error.class}: #{error.message}#{suffix}")
        payload = { component: component, operation: operation.to_s }.merge(ctx)
        Rails.error.report(error, handled: true, context: stringify_keys(payload))
      rescue StandardError => reporting_error
        Rails.logger.warn("[#{component}] HotPathErrorPolicy report failed: #{reporting_error.message}")
      end

      private

      def stringify_keys(hash)
        hash.transform_keys(&:to_s).transform_values(&:to_s)
      end
    end
  end
end
