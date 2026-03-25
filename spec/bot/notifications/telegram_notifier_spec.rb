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
  end
end
