# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::HotPathErrorPolicy do
  describe ".log_swallowed_error" do
    it "logs and reports the error as handled" do
      error = StandardError.new("boom")
      allow(Rails.logger).to receive(:error)
      allow(Rails.error).to receive(:report)

      described_class.log_swallowed_error(
        component: "TestComponent",
        operation: "test_op",
        error:     error,
        request_id: "42"
      )

      expect(Rails.logger).to have_received(:error).with(
        a_string_matching(/\[TestComponent\] test_op — StandardError: boom request_id=42/)
      )
      expect(Rails.error).to have_received(:report).with(
        error,
        handled: true,
        context: {
          "component" => "TestComponent",
          "operation" => "test_op",
          "request_id" => "42"
        }
      )
    end

    it "does not raise when the error reporter fails" do
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.error).to receive(:report).and_raise(StandardError, "reporter unavailable")

      expect {
        described_class.log_swallowed_error(
          component: "X",
          operation: "y",
          error: RuntimeError.new("original")
        )
      }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with(/HotPathErrorPolicy report failed/)
    end
  end
end
