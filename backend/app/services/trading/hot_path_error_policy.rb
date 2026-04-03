# frozen_string_literal: true

module Trading
  # Logs and reports errors on loops that must continue (shutdown, per-order cancel, fill handling).
  module HotPathErrorPolicy
    class << self
      # @param log_level [:error, :warn] +:warn+ for non-critical side effects (e.g. dashboard publish).
      def log_swallowed_error(component:, operation:, error:, log_level: :error, **context)
        ctx = context.compact
        level = normalize_log_level(log_level)
        suffix = ctx.empty? ? "" : " #{ctx.map { |k, v| "#{k}=#{v}" }.join(' ')}"
        line = "[#{component}] #{operation} — #{error.class}: #{error.message}#{suffix}"
        Rails.logger.public_send(level, line)
        payload = { component: component, operation: operation.to_s, log_level: level.to_s }.merge(ctx)
        Rails.error.report(error, handled: true, context: stringify_keys(payload))
      rescue StandardError => reporting_error
        Rails.logger.warn("[#{component}] HotPathErrorPolicy report failed: #{reporting_error.message}")
      end

      private

      def normalize_log_level(level)
        l = level.to_sym
        return l if %i[error warn].include?(l)

        :error
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s).transform_values(&:to_s)
      end
    end
  end
end
