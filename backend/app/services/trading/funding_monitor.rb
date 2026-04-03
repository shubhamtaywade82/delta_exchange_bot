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
        funding_rate_from_ticker
      end
    rescue StandardError => e
      HotPathErrorPolicy.log_swallowed_error(
        component: "FundingMonitor",
        operation: "fetch_funding_rate",
        error:     e,
        log_level: :warn,
        symbol:    @position.symbol
      )
      nil
    end

    # Delta gem has no Client#get_funding_rate; current rate is on the public ticker (see Models::Ticker).
    def funding_rate_from_ticker
      payload = @client.products.ticker(@position.symbol)
      result = payload.is_a?(Hash) ? payload[:result] : nil
      return nil unless result.is_a?(Hash)

      raw = result.with_indifferent_access[:funding_rate]
      return nil if raw.nil?

      raw.to_f
    end
  end
end
