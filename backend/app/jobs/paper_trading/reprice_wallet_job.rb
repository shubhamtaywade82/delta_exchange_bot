# frozen_string_literal: true

module PaperTrading
  class RepriceWalletJob < ApplicationJob
    queue_as :trading

    def perform(wallet_id)
      wallet = PaperWallet.find_by(id: wallet_id)
      return unless wallet

      # Preload once; +wallet.reload+ would drop this association cache and N+1 the snapshot loop below.
      positions = PaperPosition.where(paper_wallet_id: wallet.id).includes(:paper_product_snapshot).to_a
      product_ids = positions.map { |p| p.paper_product_snapshot.product_id }
      ltp_map = PaperTrading::RedisStore.get_all_ltp_for_product_ids(product_ids)

      missing = product_ids.uniq - ltp_map.keys
      PaperProductSnapshot.where(product_id: missing).find_each do |ps|
        px = ps.live_price
        ltp_map[ps.product_id] = px.to_d if px&.to_d&.positive?
      end

      wallet.reload
      wallet.refresh_snapshot!(ltp_map: ltp_map)
      PaperTrading::RedisStore.set_wallet_snapshot(wallet.id, wallet.attributes)
      Trading::PaperWalletPublisher.push_dashboard_redis_after_wallet_refresh!(wallet)

      positions.each do |pos|
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
