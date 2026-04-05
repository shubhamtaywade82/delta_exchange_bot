# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::SmcAlertEvaluationJob, type: :job do
  it "delegates to SmcAlertEvaluator.perform_evaluation!" do
    allow(Trading::Analysis::SmcAlertEvaluator).to receive(:perform_evaluation!)

    described_class.perform_now("BTCUSD")

    expect(Trading::Analysis::SmcAlertEvaluator).to have_received(:perform_evaluation!).with(symbol: "BTCUSD")
  end
end
