# frozen_string_literal: true

require "redis"
require "json"

module Bot
  module Persistence
    # Publishes live bot state (strategy signals, wallet) to Redis
    # so the Rails dashboard can read it without any database writes.
    class StatePublisher
      STRATEGY_KEY = "delta:strategy:state"
      WALLET_KEY   = "delta:wallet:state"
      WALLET_TTL   = 120  # seconds

      def initialize(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
        @redis = Redis.new(url: url)
      rescue Redis::CannotConnectError => e
        warn "[StatePublisher] Redis connect failed: #{e.message} — state publishing disabled"
        @redis = nil
      end

      # Publish per-symbol strategy evaluation state.
      # state: {
      #   h1_dir, m15_dir, adx, signal, updated_at,         # existing
      #   bos_direction, bos_level, rsi, vwap,               # new indicators
      #   vwap_deviation_pct, order_blocks,
      #   cvd_trend, cvd_delta,                              # volume
      #   oi_usd, oi_trend, funding_rate, funding_extreme,   # derivatives
      #   filters: { momentum:, volume:, derivatives: }      # filter verdicts
      # }
      def publish_strategy_state(symbol, state)
        return unless @redis && state

        @redis.hset(STRATEGY_KEY, symbol, state.to_json)
      rescue Redis::BaseError => e
        warn "[StatePublisher] publish_strategy_state failed: #{e.message}"
      end

      # Publish wallet snapshot from CapitalManager.
      def publish_wallet(available_usd:, paper_mode:, capital_inr: nil, usd_to_inr_rate: nil)
        return unless @redis

        payload = {
          available_usd:   available_usd.round(2),
          available_inr:   usd_to_inr_rate ? (available_usd * usd_to_inr_rate).round(2) : nil,
          capital_inr:     capital_inr,
          paper_mode:      paper_mode,
          updated_at:      Time.now.utc.iso8601
        }
        @redis.set(WALLET_KEY, payload.to_json, ex: WALLET_TTL)
      rescue Redis::BaseError => e
        warn "[StatePublisher] publish_wallet failed: #{e.message}"
      end
    end
  end
end
