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

  context "SMC analysis digest (chunked)" do
    let(:bot_double) { instance_double("Telegram::Bot::Client") }
    let(:api_double) { double("api") }

    it "does not send when the analysis event is disabled" do
      notifier = described_class.new(
        enabled: true,
        token: "token",
        chat_id: "123",
        event_settings: { analysis: false }
      )
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(api_double)

      expect(api_double).not_to receive(:send_message)
      notifier.notify_smc_analysis_digest(symbol: "BTCUSD", plain_text: "long text")
    end

    it "sends one message for a short summary" do
      notifier = described_class.new(
        enabled: true,
        token: "token",
        chat_id: "123",
        event_settings: { analysis: true }
      )
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(api_double)

      expect(api_double).to receive(:send_message).once.with(
        hash_including(
          chat_id: "123",
          parse_mode: "HTML",
          text: a_string_including("SMC ANALYSIS", "BTCUSD", "1/1", "hello")
        )
      )
      notifier.notify_smc_analysis_digest(symbol: "BTCUSD", plain_text: "hello")
    end

    it "sends multiple messages when the body exceeds the chunk size" do
      notifier = described_class.new(
        enabled: true,
        token: "token",
        chat_id: "123",
        event_settings: { analysis: true }
      )
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(api_double)
      allow(notifier).to receive(:sleep)

      long = ("A" * 2_000 + "\n\n" + "B" * 2_000)
      expect(api_double).to receive(:send_message).twice
      notifier.notify_smc_analysis_digest(symbol: "SOLUSD", plain_text: long)
    end
  end

  context "SMC confluence event alert" do
    let(:bot_double) { instance_double("Telegram::Bot::Client") }
    let(:api_double) { double("api") }

    it "does not send when analysis events are disabled" do
      notifier = described_class.new(
        enabled: true,
        token: "token",
        chat_id: "123",
        event_settings: { analysis: false }
      )
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(api_double)

      expect(api_double).not_to receive(:send_message)
      notifier.notify_smc_confluence_event(symbol: "BTCUSD", title: "T", message_line: "M", ltp: 1.0, resolution: "5m")
    end

    it "includes title, timeframe, body, and close when enabled" do
      notifier = described_class.new(
        enabled: true,
        token: "token",
        chat_id: "123",
        event_settings: { analysis: true }
      )
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(api_double)

      expect(api_double).to receive(:send_message).with(
        hash_including(
          parse_mode: "HTML",
          text: a_string_including("CHOCH Bullish", "BTCUSD", "5m", "structure shifted", "Close: $100.50")
        )
      )
      notifier.notify_smc_confluence_event(
        symbol: "BTCUSD",
        title: "CHOCH Bullish",
        message_line: "structure shifted",
        ltp: 100.5,
        resolution: "5m"
      )
    end

    it "sends a follow-up AI message when ai_insight is present" do
      notifier = described_class.new(
        enabled: true,
        token: "token",
        chat_id: "123",
        event_settings: { analysis: true }
      )
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(api_double)

      expect(api_double).to receive(:send_message).exactly(2).times
      notifier.notify_smc_confluence_event(
        symbol: "BTCUSD",
        title: "T",
        message_line: "M",
        ltp: nil,
        resolution: nil,
        ai_insight: "Ollama summary for this SMC event."
      )
    end
  end
end
