# frozen_string_literal: true

module PaperTrading
  # Applies periodic funding cashflows to the INR ledger using current open positions.
  class FundingApplier
    def initialize(wallet:, usd_inr_rate: Finance::UsdInrRate.current)
      @wallet = wallet
      @usd_inr_rate = usd_inr_rate.to_d
    end

    # @param funding_rate [BigDecimal, Numeric] funding rate per interval (e.g. 0.0001)
    # @param mark_prices [Hash{Integer=>BigDecimal}] product_id => mark price
    # @param as_of [Time]
    def call(funding_rate:, mark_prices:, as_of: Time.current)
      rate = funding_rate.to_d
      return if rate.zero?
      interval_seconds = funding_interval_seconds

      @wallet.with_lock do
        writer = WalletLedgerEntry.new(wallet: @wallet)

        @wallet.paper_positions.includes(:paper_product_snapshot).find_each do |position|
          mark = mark_prices[position.paper_product_snapshot.product_id]&.to_d
          next unless mark&.positive?

          notional_usd = position.net_quantity.to_d * position.paper_product_snapshot.contract_value.to_d * mark
          direction = position.side == "buy" ? -1.to_d : 1.to_d
          elapsed_seconds = funding_elapsed_seconds(position:, as_of:)
          prorata = elapsed_seconds / interval_seconds
          payment_inr = (notional_usd * rate * direction * prorata * @usd_inr_rate).round(2)
          next if payment_inr.zero?

          writer.funding!(
            amount_inr: payment_inr,
            meta: {
              "product_id" => position.paper_product_snapshot.product_id,
              "side" => position.side,
              "rate" => rate.to_s("F"),
              "as_of" => as_of.iso8601
            }
          )
          position.update!(last_funding_at: as_of)
        end

        @wallet.recompute_from_ledger!
      end
    end

    private

    def funding_interval_seconds
      configured = ENV["PAPER_FUNDING_INTERVAL_SECONDS"]&.to_i
      value = configured&.positive? ? configured : 8.hours.to_i
      value.to_d
    end

    def funding_elapsed_seconds(position:, as_of:)
      last = position.last_funding_at
      return funding_interval_seconds if last.nil?

      [ as_of.to_i - last.to_i, 0 ].max.to_d
    end
  end
end
