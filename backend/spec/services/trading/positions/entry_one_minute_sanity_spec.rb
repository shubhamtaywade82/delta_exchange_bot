# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Positions::EntryOneMinuteSanity do
  let(:portfolio) { create(:portfolio) }
  let(:session) { create(:trading_session, portfolio: portfolio) }
  let(:bar_open) { Time.utc(2026, 4, 2, 14, 28, 0) }
  let(:fill_time) { Time.utc(2026, 4, 2, 14, 28, 27) }
  let(:market_data) { instance_double("MarketData") }

  def candle_payload(close:, ts: bar_open.to_i)
    { "result" => [{ "open" => close - 1, "high" => close + 1, "low" => close - 2, "close" => close, "volume" => 1,
                     "timestamp" => ts }] }
  end

  it "marks OK when VWAP and first fill are near the 1m close for that minute" do
    position = create(:position,
                        portfolio: portfolio,
                        symbol: "BTCUSD",
                        side: "short",
                        status: "filled",
                        entry_price: 100.0,
                        size: 1.0,
                        leverage: 10)
    order = create(:order,
                   trading_session: session,
                   portfolio: portfolio,
                   position: position,
                   symbol: "BTCUSD",
                   side: "sell",
                   size: "1.0",
                   status: "filled")
    create(:fill,
           order: order,
           price: 100.0,
           quantity: 1.0,
           filled_at: fill_time,
           exchange_fill_id: "f-entry-sanity-1")

    allow(market_data).to receive(:candles).and_return(candle_payload(close: 100.05))

    rows = described_class.call(positions: Position.where(id: position.id), tolerance_pct: 0.25, market_data: market_data)
    expect(rows.size).to eq(1)
    expect(rows.first).to have_attributes(ok: true, fill_count: 1, candle_close: 100.05)
    expect(rows.first.note).to be_nil
  end

  it "flags when close deviates beyond tolerance" do
    position = create(:position,
                        portfolio: portfolio,
                        symbol: "BTCUSD",
                        side: "short",
                        status: "filled",
                        entry_price: 100.0,
                        size: 1.0,
                        leverage: 10)
    order = create(:order,
                   trading_session: session,
                   portfolio: portfolio,
                   position: position,
                   symbol: "BTCUSD",
                   side: "sell",
                   size: "1.0",
                   status: "filled")
    create(:fill,
           order: order,
           price: 100.0,
           quantity: 1.0,
           filled_at: fill_time,
           exchange_fill_id: "f-entry-sanity-2")

    allow(market_data).to receive(:candles).and_return(candle_payload(close: 110.0))

    rows = described_class.call(positions: Position.where(id: position.id), tolerance_pct: 0.25, market_data: market_data)
    expect(rows.first.ok).to be(false)
  end

  it "flags a single fill when stored entry drifts materially from that fill even if the fill matches the 1m close" do
    position = create(:position,
                      portfolio: portfolio,
                      symbol: "BTCUSD",
                      side: "short",
                      status: "filled",
                      entry_price: 106.0,
                      size: 1.0,
                      leverage: 10)
    order = create(:order,
                   trading_session: session,
                   portfolio: portfolio,
                   position: position,
                   symbol: "BTCUSD",
                   side: "sell",
                   size: "1.0",
                   status: "filled")
    create(:fill,
           order: order,
           price: 100.0,
           quantity: 1.0,
           filled_at: fill_time,
           exchange_fill_id: "f-entry-drift")

    allow(market_data).to receive(:candles).and_return(candle_payload(close: 100.05))

    rows = described_class.call(positions: Position.where(id: position.id), tolerance_pct: 1.0, market_data: market_data)
    expect(rows.first.ok).to be(false)
    expect(rows.first.diff_first_fill_vs_close_pct).to be <= 1.0
    expect(rows.first.note).to include("reconcile")
  end

  it "matches when Delta uses period-end time for the candle row" do
    position = create(:position,
                        portfolio: portfolio,
                        symbol: "BTCUSD",
                        side: "short",
                        status: "filled",
                        entry_price: 100.0,
                        size: 1.0,
                        leverage: 10)
    order = create(:order,
                   trading_session: session,
                   portfolio: portfolio,
                   position: position,
                   symbol: "BTCUSD",
                   side: "sell",
                   size: "1.0",
                   status: "filled")
    create(:fill,
           order: order,
           price: 100.0,
           quantity: 1.0,
           filled_at: fill_time,
           exchange_fill_id: "f-close-anchor")

    bar_end = bar_open + 60.seconds
    allow(market_data).to receive(:candles).and_return(
      candle_payload(close: 100.02, ts: bar_end.to_i)
    )

    rows = described_class.call(positions: Position.where(id: position.id), tolerance_pct: 0.25, market_data: market_data)
    expect(rows.first).to have_attributes(ok: true, candle_close: 100.02)
  end

  it "adds a note when multiple fills shaped the VWAP" do
    position = create(:position,
                        portfolio: portfolio,
                        symbol: "BTCUSD",
                        side: "short",
                        status: "filled",
                        entry_price: 101.0,
                        size: 2.0,
                        leverage: 10)
    order = create(:order,
                   trading_session: session,
                   portfolio: portfolio,
                   position: position,
                   symbol: "BTCUSD",
                   side: "sell",
                   size: "2.0",
                   status: "filled")
    create(:fill,
           order: order,
           price: 100.0,
           quantity: 1.0,
           filled_at: fill_time,
           exchange_fill_id: "f-a")
    create(:fill,
           order: order,
           price: 102.0,
           quantity: 1.0,
           filled_at: fill_time + 30.seconds,
           exchange_fill_id: "f-b")

    allow(market_data).to receive(:candles).and_return(candle_payload(close: 100.0))

    rows = described_class.call(positions: Position.where(id: position.id), tolerance_pct: 0.25, market_data: market_data)
    expect(rows.first.fill_count).to eq(2)
    expect(rows.first).to have_attributes(ok: true, diff_first_fill_vs_close_pct: 0.0)
    expect(rows.first.diff_entry_vs_close_pct).to be > 0.25
    expect(rows.first.note).to include("VWAP")
  end

  it "counts fills from all orders on the symbol (same scope as PositionRecalculator)" do
    position = create(:position,
                        portfolio: portfolio,
                        symbol: "BTCUSD",
                        side: "short",
                        status: "partially_filled",
                        entry_price: 101.0,
                        size: 2.0,
                        leverage: 10)
    o1 = create(:order,
                trading_session: session,
                portfolio: portfolio,
                position: position,
                symbol: "BTCUSD",
                side: "sell",
                size: "1.0",
                status: "filled")
    o2 = create(:order,
                trading_session: session,
                portfolio: portfolio,
                position: nil,
                symbol: "BTCUSD",
                side: "sell",
                size: "1.0",
                status: "filled")
    create(:fill, order: o1, price: 100.0, quantity: 1.0, filled_at: fill_time, exchange_fill_id: "f-o1")
    create(:fill, order: o2, price: 102.0, quantity: 1.0, filled_at: fill_time + 1.second, exchange_fill_id: "f-o2")

    allow(market_data).to receive(:candles).and_return(candle_payload(close: 101.0))

    rows = described_class.call(positions: Position.where(id: position.id), tolerance_pct: 1.0, market_data: market_data)
    expect(rows.first.fill_count).to eq(2)
    expect(rows.first.note).to include("VWAP")
  end

  it "includes closed positions with entry in default_positions_scope" do
    active_row = create(:position,
                        portfolio: portfolio,
                        symbol: "BTCUSD",
                        side: "short",
                        status: "filled",
                        entry_price: 100.0,
                        size: 1.0,
                        leverage: 10)
    closed_row = create(:position,
                        portfolio: portfolio,
                        symbol: "ETHUSD",
                        side: "short",
                        status: "closed",
                        entry_price: 50.0,
                        size: 0,
                        leverage: 10)

    ids = described_class.default_positions_scope.pluck(:id)
    expect(ids).to include(active_row.id, closed_row.id)
  end

  it "uses only fills from orders linked to the position when the row is closed" do
    closed = create(:position,
                    portfolio: portfolio,
                    symbol: "BTCUSD",
                    side: "short",
                    status: "closed",
                    entry_price: 100.0,
                    size: 0,
                    leverage: 10)
    active = create(:position,
                    portfolio: portfolio,
                    symbol: "BTCUSD",
                    side: "short",
                    status: "filled",
                    entry_price: 200.0,
                    size: 1.0,
                    leverage: 10)

    old_order = create(:order,
                       trading_session: session,
                       portfolio: portfolio,
                       position: closed,
                       symbol: "BTCUSD",
                       side: "sell",
                       size: "1.0",
                       status: "filled")
    create(:fill,
           order: old_order,
           price: 100.0,
           quantity: 1.0,
           filled_at: fill_time,
           exchange_fill_id: "f-closed-cycle")

    new_order = create(:order,
                       trading_session: session,
                       portfolio: portfolio,
                       position: active,
                       symbol: "BTCUSD",
                       side: "sell",
                       size: "1.0",
                       status: "filled")
    create(:fill,
           order: new_order,
           price: 200.0,
           quantity: 1.0,
           filled_at: fill_time + 1.hour,
           exchange_fill_id: "f-active-cycle")

    allow(market_data).to receive(:candles).and_return(candle_payload(close: 100.05))

    closed_rows = described_class.call(positions: Position.where(id: closed.id), tolerance_pct: 0.25, market_data: market_data)
    expect(closed_rows.first).to have_attributes(first_fill_price: 100.0, fill_count: 1, ok: true)

    active_rows = described_class.call(positions: Position.where(id: active.id), tolerance_pct: 50.0, market_data: market_data)
    expect(active_rows.first.fill_count).to eq(2)
    expect(active_rows.first.first_fill_price).to eq(100.0)
  end
end
