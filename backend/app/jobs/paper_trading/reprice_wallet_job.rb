# frozen_string_literal: true

module PaperTrading
  class RepriceWalletJob < ApplicationJob
    queue_as :trading

    def perform(wallet_id)
      wallet = PaperWallet.includes(paper_positions: :paper_product_snapshot).find_by(id: wallet_id)
      return unless wallet

      product_ids = wallet.paper_positions.map { |p| p.paper_product_snapshot.product_id }
      ltp_map = PaperTrading::RedisStore.get_all_ltp_for_product_ids(product_ids)

      missing = product_ids - ltp_map.keys
      PaperProductSnapshot.where(product_id: missing).find_each do |ps|
        px = ps.live_price
        ltp_map[ps.product_id] = px.to_d if px&.to_d&.positive?
      end

      wallet.reload
      wallet.refresh_snapshot!(ltp_map: ltp_map)
      PaperTrading::RedisStore.set_wallet_snapshot(wallet.id, wallet.attributes)

      wallet.paper_positions.each do |pos|
        pid = pos.paper_product_snapshot.product_id
        PaperTrading::RedisStore.set_position_json(
          wallet.id,
          pid,
          pos.attributes.slice("side", "net_quantity", "avg_entry_price", "risk_unit_per_contract")
        )
      end
    end
  end
end
