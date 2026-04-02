# frozen_string_literal: true

namespace :paper_wallet do
  desc "Deposit INR into a paper wallet (ledger entry). Usage: WALLET_ID=1 AMOUNT_INR=50000 bin/rails paper_wallet:deposit"
  task deposit: :environment do
    id = ENV.fetch("WALLET_ID", nil)
    amount = ENV.fetch("AMOUNT_INR", nil)
    abort "WALLET_ID and AMOUNT_INR are required" if id.blank? || amount.blank?

    wallet = PaperWallet.find_by(id: id)
    unless wallet
      rows = PaperWallet.order(:id).limit(20).pluck(:id, :name)
      if rows.empty?
        abort <<~MSG

          No PaperWallet with id=#{id.inspect}. There are no paper wallets yet.

          Create one in the Rails console, e.g.:

            PaperWallet.create!(name: "default")

          Then run this task again with that wallet's id.
        MSG
      else
        listing = rows.map { |(wid, name)| "  id=#{wid}  name=#{name.inspect}" }.join("\n")
        abort <<~MSG

          No PaperWallet with id=#{id.inspect}. Existing wallets:

          #{listing}

          Use one of the ids above, e.g. WALLET_ID=#{rows.first.first} AMOUNT_INR=#{amount} bin/rails paper_wallet:deposit
        MSG
      end
    end
    wallet.deposit!(BigDecimal(amount), meta: { "source" => "rake" })
    wallet.refresh_snapshot!(ltp_map: {})
    puts "Deposited #{amount} INR into wallet #{wallet.id}. balance_inr=#{wallet.balance_inr} available_inr=#{wallet.available_inr}"
  end
end
