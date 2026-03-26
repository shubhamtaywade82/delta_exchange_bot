# app/services/trading/events/position_updated.rb
module Trading
  module Events
    PositionUpdated = Struct.new(:symbol, :side, :size, :entry_price,
                                  :mark_price, :unrealized_pnl, :status, keyword_init: true)
  end
end
