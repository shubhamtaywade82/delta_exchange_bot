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

    rows = described_class.call(positions: Position.where(id: position.id), tolerance_pct: 50.0, market_data: market_data)
    expect(rows.first.fill_count).to eq(2)
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
end
