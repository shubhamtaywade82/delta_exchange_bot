# frozen_string_literal: true

require "json"
require "fileutils"

module Bot
  module Notifications
    class Logger
      LEVELS = %w[debug info warn error].freeze

      def initialize(file:, level: "info")
        @file = file
        @min_level = LEVELS.index(level.to_s) || 1
        FileUtils.mkdir_p(File.dirname(@file))
      end

      def debug(event, **payload) = log("debug", event, payload)
      def info(event, **payload)  = log("info",  event, payload)
      def warn(event, **payload)  = log("warn",  event, payload)
      def error(event, **payload) = log("error", event, payload)

      private

      def log(level, event, payload)
        return if LEVELS.index(level) < @min_level

        entry = { ts: Time.now.utc.iso8601, level: level, event: event }.merge(payload)
        File.open(@file, "a") { |f| f.puts(entry.to_json) }
      end
    end
  end
end
