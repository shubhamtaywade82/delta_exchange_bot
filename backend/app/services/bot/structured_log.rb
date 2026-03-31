# frozen_string_literal: true

module Bot
  # Bot::Notifications::Logger uses event + keyword payload; Rails.logger / stdlib Logger accept one string.
  module StructuredLog
    module_function

    def log(logger, level, event, **payload)
      if logger.is_a?(Bot::Notifications::Logger)
        logger.public_send(level, event, **payload)
      else
        line = payload.empty? ? event.to_s : "#{event} #{payload.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")}"
        logger&.public_send(level, line)
      end
    end
  end
end
