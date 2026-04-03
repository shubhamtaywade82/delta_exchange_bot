# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Notifications::TelegramNotifier do
  context "when disabled" do
    subject(:notifier) { described_class.new(enabled: false, token: "", chat_id: "") }

    it "does not raise and returns nil when sending" do
      expect { notifier.send_message("hello") }.not_to raise_error
    end
  end

  context "when enabled" do
    let(:bot_double) { instance_double("Telegram::Bot::Client") }
    subject(:notifier) { described_class.new(enabled: true, token: "token", chat_id: "123") }

    before do
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(double(send_message: true))
    end

    it "calls the Telegram API" do
      expect(bot_double.api).to receive(:send_message).with(chat_id: "123", text: "hello", parse_mode: "HTML")
      notifier.send_message("hello")
    end

    it "sends event notification when enabled for event" do
      expect(bot_double.api).to receive(:send_message).with(
        hash_including(chat_id: "123", parse_mode: "HTML", text: include("SIGNAL"))
      )
      notifier.notify_signal_generated(symbol: "BTCUSD", side: :long, price: 42_000.0, strategy: "multi_timeframe")
    end

    it "labels first open as POSITION OPENED" do
      expect(bot_double.api).to receive(:send_message).with(
        hash_including(text: include("POSITION OPENED"))
      )
      notifier.notify_trade_opened(
        symbol: "BTCUSD", side: :short, price: 66_000.0, lots: 10.0, added_lots: 10.0,
        leverage: 20, trailing_stop: 67_000.0, mode: "paper"
      )
    end

    it "labels add-on fill as POSITION SCALED with delta and total" do
      expect(bot_double.api).to receive(:send_message).with(
        hash_including(text: a_string_including("POSITION SCALED", "+Lots this fill"))
      )
      notifier.notify_trade_opened(
        symbol: "BTCUSD", side: :short, price: 66_500.0, lots: 13.0, added_lots: 3.0,
        leverage: 20, trailing_stop: 67_000.0, mode: "paper"
      )
    end

    it "appends position_id to POSITION CLOSED when provided" do
      expect(bot_double.api).to receive(:send_message).with(
        hash_including(text: a_string_including("POSITION CLOSED", "position_id=42"))
      )
      notifier.notify_trade_closed(
        symbol: "BTCUSD",
        exit_price: 50_000.0,
        pnl_usd: 0.0,
        pnl_inr: 0.0,
        duration_seconds: 0,
        reason: "TEST",
        position_id: 42
      )
    end

    it "logs a single-line error to Rails-style loggers when the API fails" do
      rails_logger = instance_double(ActiveSupport::Logger)
      notifier = described_class.new(enabled: true, token: "token", chat_id: "123", logger: rails_logger)
      allow(notifier).to receive(:client).and_raise(StandardError, "telegram down")

      expect(rails_logger).to receive(:error).with("[TelegramNotifier] telegram_send_failed: telegram down")
      notifier.send_message("hello")
    end
  end

  context "when event is disabled" do
    let(:bot_double) { instance_double("Telegram::Bot::Client") }
    subject(:notifier) do
      described_class.new(
        enabled: true,
        token: "token",
        chat_id: "123",
        event_settings: { signals: false }
      )
    end

    before do
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(double(send_message: true))
    end

    it "does not call the Telegram API for that event" do
      expect(bot_double.api).not_to receive(:send_message)
      notifier.notify_signal_generated(symbol: "BTCUSD", side: :short, price: 41_000.0, strategy: "multi_timeframe")
    end
  end
end
