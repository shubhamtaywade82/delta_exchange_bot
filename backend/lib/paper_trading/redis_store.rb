# frozen_string_literal: true

require "bigdecimal"
require "json"

module PaperTrading
  module RedisStore
    KEYS = {
      ltp: "delta:ltp:%<product_id>d",
      product_snapshot: "delta:product:%<product_id>d",
      wallet_snapshot: "paper:wallet:%<wallet_id>d:snapshot",
      position: "paper:position:%<wallet_id>d:%<product_id>d",
      signal_status: "paper:signal:%<signal_id>d"
    }.freeze

    TTL = {
      ltp: 30,
      product_snapshot: 3600,
      wallet_snapshot: 60,
      position: 120,
      signal_status: 86_400
    }.freeze

    module_function

    def redis
      Redis.current
    end

    def dual_write_ltp_cache?
      ENV["PAPER_BROKER_DUAL_WRITE_LTP_CACHE"] != "0"
    end

    def get_ltp(product_id)
      val = redis.get(format(KEYS[:ltp], product_id: product_id))
      val.present? ? BigDecimal(val) : nil
    end

    def set_ltp(product_id, price, symbol: nil)
      redis.setex(
        format(KEYS[:ltp], product_id: product_id),
        TTL[:ltp],
        price.to_d.to_s("F")
      )
      return unless dual_write_ltp_cache? && symbol.present?

      Rails.cache.write("ltp:#{symbol}", price.to_d)
    end

    def set_product_json(product_id, payload)
      redis.setex(
        format(KEYS[:product_snapshot], product_id: product_id),
        TTL[:product_snapshot],
        payload.is_a?(String) ? payload : JSON.generate(payload)
      )
    end

    def get_wallet_snapshot(wallet_id)
      raw = redis.get(format(KEYS[:wallet_snapshot], wallet_id: wallet_id))
      raw.present? ? JSON.parse(raw, symbolize_names: true) : nil
    end

    def set_wallet_snapshot(wallet_id, attrs)
      payload = attrs.stringify_keys.slice(
        "cash_balance", "realized_pnl", "unrealized_pnl", "equity", "reserved_margin"
      ).transform_values(&:to_s)
      redis.setex(
        format(KEYS[:wallet_snapshot], wallet_id: wallet_id),
        TTL[:wallet_snapshot],
        JSON.generate(payload)
      )
    end

    def set_position_json(wallet_id, product_id, position_hash)
      redis.setex(
        format(KEYS[:position], wallet_id: wallet_id, product_id: product_id),
        TTL[:position],
        JSON.generate(position_hash)
      )
    end

    def get_all_ltp_for_product_ids(product_ids)
      ids = Array(product_ids).uniq
      return {} if ids.empty?

      keys = ids.map { |id| format(KEYS[:ltp], product_id: id) }
      values = redis.mget(*keys)
      ids.each_with_index.each_with_object({}) do |(id, idx), acc|
        val = values[idx]
        acc[id] = BigDecimal(val) if val.present?
      end
    end
  end
end
