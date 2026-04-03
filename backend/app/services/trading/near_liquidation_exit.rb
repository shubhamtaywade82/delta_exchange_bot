# frozen_string_literal: true

module Trading
  # Force-exits positions when last trade price is within a small band of the exchange-reported
  # liquidation threshold. Distinct from +Trading::Risk::LiquidationGuard+, which classifies margin ratio.
  class NearLiquidationExit
    BUFFER_PCT = 0.10
    COOLDOWN_TTL = 30.seconds

    def self.check_all(client:)
      return if PaperTrading.enabled?

      # Intentionally all active rows (runner may watch multiple portfolios / sessions).
      Position.active.find_each do |position|
        new(position, client).check!
      end
    end

    def initialize(position, client)
      @position = position
      @client   = client
    end

    def check!
      return unless @position.liquidation_price.present?
      return if Rails.cache.read(cooldown_cache_key)

      mark = MarkPrice.for_synthetic_exit(@position, fallback_entry_price: false)
      current_price = mark&.to_f
      return unless current_price&.positive?

      return unless distance_to_liquidation(current_price) < BUFFER_PCT

      Rails.logger.warn(
        "[NearLiquidationExit] Emergency exit: #{@position.symbol} price=#{current_price} " \
        "liq=#{@position.liquidation_price} distance=#{(distance_to_liquidation(current_price) * 100).round(2)}%"
      )
      Rails.cache.write(cooldown_cache_key, 1, expires_in: COOLDOWN_TTL)
      EmergencyShutdown.force_exit_position(@position, @client)
    end

    private

    def cooldown_cache_key
      "near_liquidation_exit_attempt:#{@position.id}"
    end

    def distance_to_liquidation(current_price)
      liq = @position.liquidation_price.to_f
      if @position.side == "long"
        (current_price - liq) / current_price
      else
        (liq - current_price) / current_price
      end
    end
  end
end
