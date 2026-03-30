# frozen_string_literal: true

module Trading
  class FundingMonitor
    HIGH_FUNDING_THRESHOLD = 0.001  # 0.1% funding rate

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
      rate = fetch_funding_rate
      return unless rate

      if rate.abs >= HIGH_FUNDING_THRESHOLD
        side_note = rate.positive? ? "longs paying shorts" : "shorts paying longs"
        Rails.logger.warn(
          "[FundingMonitor] High funding #{(rate * 100).round(4)}% for #{@position.symbol} (#{side_note})"
        )
        EventBus.publish(:high_funding_detected, {
          symbol:   @position.symbol,
          rate:     rate,
          position: @position
        })
      end
    end

    private

    def fetch_funding_rate
      Rails.cache.fetch("funding:#{@position.symbol}", expires_in: 5.minutes) do
        @client.get_funding_rate(@position.symbol)
      end
    rescue => e
      Rails.logger.warn("[FundingMonitor] Could not fetch funding rate for #{@position.symbol}: #{e.message}")
      nil
    end
  end
end
