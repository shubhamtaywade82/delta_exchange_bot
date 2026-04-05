# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::TelegramNotifications do
  describe ".deliver" do
    it "swallows errors from the notifier so trading never crashes on Telegram" do
      allow(Bot::Config).to receive(:load).and_raise(StandardError, "config down")
      allow(Rails.error).to receive(:report)

      expect {
        described_class.deliver { |n| n.send_message("x") }
      }.not_to raise_error

      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "config down"),
        handled: true,
        context: hash_including("component" => "TelegramNotifications", "operation" => "deliver")
      )
    end
  end
end
