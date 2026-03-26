# frozen_string_literal: true

require "json"
require "fileutils"

module Bot
  module Notifications
    class Logger
      LEVELS = %w[debug info warn error].freeze

      def initialize(file:, level: "info")
        raise ArgumentError, "Unknown log level: #{level}" unless LEVELS.include?(level.to_s)

        @min_level = LEVELS.index(level.to_s)
        @mutex     = Mutex.new
        FileUtils.mkdir_p(File.dirname(file))
        @io = File.open(file, "a")
        @io.sync = true  # flush immediately on each write
      end

      def debug(event, **payload) = log("debug", event, payload)
      def info(event, **payload)  = log("info",  event, payload)
      def warn(event, **payload)  = log("warn",  event, payload)
      def error(event, **payload) = log("error", event, payload)

      def close
        @mutex.synchronize { @io.close }
      end

      private

      def log(level, event, payload)
        return if LEVELS.index(level) < @min_level

        entry = { ts: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"), level: level, event: event }.merge(payload)
        @mutex.synchronize { @io.write("#{entry.to_json}\n") }
      end
    end
  end
end
