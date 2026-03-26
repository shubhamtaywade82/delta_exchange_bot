# frozen_string_literal: true

module Trading
  class LiquidationGuard
    BUFFER_PCT = 0.10  # force exit if within 10% of liquidation price

    def self.check_all(client:)
      Position.where(status: "open").each do |position|
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

      if distance_to_liquidation(current_price) < BUFFER_PCT
        Rails.logger.warn(
          "[LiquidationGuard] Emergency exit: #{@position.symbol} price=#{current_price} " \
          "liq=#{@position.liquidation_price} distance=#{(distance_to_liquidation(current_price) * 100).round(2)}%"
        )
        KillSwitch.force_exit_position(@position, @client)
      end
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
