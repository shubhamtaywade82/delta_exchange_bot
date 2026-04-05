# frozen_string_literal: true

module PaperTrading
  class ApplyFundingJob < ApplicationJob
    queue_as :risk

    def perform(wallet_id, funding_rate, mark_prices = {})
      wallet = PaperWallet.find_by(id: wallet_id)
      return unless wallet

      FundingApplier.new(wallet: wallet).call(
        funding_rate: funding_rate,
        mark_prices: mark_prices.transform_keys(&:to_i),
        as_of: Time.current
      )
    end
  end
end
