# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::PositionReconciliation do
  describe ".recalculate_all_active!" do
    it "skips failed rows, increments only successes, and reports each failure" do
      create(:position, status: "filled", symbol: "BTCUSD")
      allow(Trading::PositionRecalculator).to receive(:call).and_raise(StandardError, "recalc failed")
      allow(Rails.logger).to receive(:info)
      allow(Rails.error).to receive(:report)

      count = described_class.recalculate_all_active!

      expect(count).to eq(0)
      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "recalc failed"),
        handled: true,
        context: hash_including(
          "component" => "PositionReconciliation",
          "operation" => "recalculate_all_active!"
        )
      )
    end
  end
end
