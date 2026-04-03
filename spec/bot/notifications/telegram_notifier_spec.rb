# frozen_string_literal: true

require "spec_helper"
require "bot/notifications/telegram_notifier"

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
