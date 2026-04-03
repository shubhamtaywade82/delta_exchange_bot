# frozen_string_literal: true

module Trading
  # Force-exits positions when last trade price is within a small band of the exchange-reported
  # liquidation threshold. Distinct from +Trading::Risk::LiquidationGuard+, which classifies margin ratio.
  class NearLiquidationExit
    BUFFER_PCT = 0.10

    def self.check_all(client:)
      Position.active.each do |position|
        new(position, client).check!
      end
    end

    def initialize(position, client)
      @position = position
      @client   = client
    end

    def check!
      return unless @position.liquidation_price.present?

      current_price = Rails.cache.read("ltp:#{@position.symbol}")&.to_f
      return unless current_price&.positive?

      return unless distance_to_liquidation(current_price) < BUFFER_PCT

      Rails.logger.warn(
        "[NearLiquidationExit] Emergency exit: #{@position.symbol} price=#{current_price} " \
        "liq=#{@position.liquidation_price} distance=#{(distance_to_liquidation(current_price) * 100).round(2)}%"
      )
      EmergencyShutdown.force_exit_position(@position, @client)
    end

    private

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
