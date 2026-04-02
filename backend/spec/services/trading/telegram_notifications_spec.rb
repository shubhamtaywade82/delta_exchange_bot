# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::TelegramNotifications do
  describe ".deliver" do
    it "swallows errors from the notifier so trading never crashes on Telegram" do
      allow(Bot::Config).to receive(:load).and_raise(StandardError, "config down")

      expect {
        described_class.deliver { |n| n.send_message("x") }
      }.not_to raise_error
    end
  end
end
