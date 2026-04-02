# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Handlers::TrailingStopHandler do
  let(:portfolio) { create(:portfolio) }
  let(:position) do
    create(
      :position,
      portfolio: portfolio,
      symbol: "BTCUSD",
      side: "short",
      status: "filled",
      size: 1.0,
      entry_price: 100_000.0,
      leverage: 10,
      peak_price: 99_000.0,
      stop_price: 100_000.0,
      trail_pct: 1.0
    )
  end
  let(:tick) { Trading::Events::TickReceived.new(symbol: "BTCUSD", price: 100_100.0) }
  let(:client) { instance_double(DeltaExchange::Client) }

  before do
    allow(PositionsRepository).to receive(:open_for).with("BTCUSD").and_return(position)
    allow(Trading::EmergencyShutdown).to receive(:force_exit_position)
    Rails.cache.clear
  end

  it "notifies trailing stop at most once per position within the dedupe window" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    notifier = instance_double(Bot::Notifications::TelegramNotifier)
    allow(notifier).to receive(:notify_trailing_stop_triggered)
    expect(notifier).to receive(:notify_trailing_stop_triggered).once
    allow(Trading::TelegramNotifications).to receive(:deliver).and_yield(notifier)

    described_class.new(tick, client: client).call
    described_class.new(tick, client: client).call
  ensure
    Rails.cache = previous_cache
  end
end
