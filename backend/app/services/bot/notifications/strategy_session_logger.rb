# frozen_string_literal: true

module Bot
  module Notifications
    # JSON lines to bot.log (same shape as +Logger+) plus plain-text lines on +rails_logger+ for development.log / STDOUT.
    class StrategySessionLogger
      def initialize(file:, level:, rails_logger:)
        @file = Logger.new(file: file, level: level)
        @rails = rails_logger
      end

      def debug(event, **payload)
        @file.debug(event, **payload)
        mirror_rails(:debug, event, payload)
      end

      def info(event, **payload)
        @file.info(event, **payload)
        mirror_rails(:info, event, payload)
      end

      def warn(event, **payload)
        @file.warn(event, **payload)
        mirror_rails(:warn, event, payload)
      end

      def error(event, **payload)
        @file.error(event, **payload)
        mirror_rails(:error, event, payload)
      end

      def close
        @file.close
      end

      private

      def mirror_rails(level, event, payload)
        return unless @rails

        line =
          if payload.empty?
            event.to_s
          else
            "#{event} #{payload.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")}"
          end
        @rails.public_send(level, line)
      end
    end
  end
end
