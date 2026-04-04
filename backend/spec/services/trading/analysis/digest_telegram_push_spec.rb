# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::DigestTelegramPush do
  describe ".deliver_row" do
    it "does not call Telegram when ai_insight is blank" do
      allow(Trading::TelegramNotifications).to receive(:deliver)
      described_class.deliver_row({ "symbol" => "BTCUSD", "ai_insight" => "", "error" => nil })
      expect(Trading::TelegramNotifications).not_to have_received(:deliver)
    end

    it "does not call Telegram when the row has an error" do
      allow(Trading::TelegramNotifications).to receive(:deliver)
      described_class.deliver_row({ "symbol" => "BTCUSD", "ai_insight" => "x", "error" => "failed" })
      expect(Trading::TelegramNotifications).not_to have_received(:deliver)
    end

    it "uses ai_smc.summary when ai_insight is missing" do
      notifier = instance_double(Bot::Notifications::TelegramNotifier)
      allow(Trading::TelegramNotifications).to receive(:deliver).and_yield(notifier)
      expect(notifier).to receive(:notify_smc_analysis_digest).with(symbol: "ETHUSD", plain_text: "from json")
      described_class.deliver_row(
        { "symbol" => "ETHUSD", "ai_smc" => { "summary" => "from json" } }
      )
    end

    it "prefers ai_insight over ai_smc.summary" do
      notifier = instance_double(Bot::Notifications::TelegramNotifier)
      allow(Trading::TelegramNotifications).to receive(:deliver).and_yield(notifier)
      expect(notifier).to receive(:notify_smc_analysis_digest).with(symbol: "BTCUSD", plain_text: "primary")
      described_class.deliver_row(
        {
          "symbol" => "BTCUSD",
          "ai_insight" => "primary",
          "ai_smc" => { "summary" => "secondary" }
        }
      )
    end
  end
end
