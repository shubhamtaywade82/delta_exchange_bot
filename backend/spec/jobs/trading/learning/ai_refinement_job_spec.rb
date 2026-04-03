require "rails_helper"

RSpec.describe Trading::Learning::AiRefinementJob, type: :job do
  before do
    allow(Trading::Learning::AiRefinementTrigger).to receive(:call)
  end

  it "applies strategy bounds and runtime settings from AI payload" do
    StrategyParam.create!(strategy: "scalping", regime: "trending", aggression: 0.95, risk_multiplier: 1.8)
    Trade.create!(
      symbol: "BTCUSD", side: "buy", size: 1, entry_price: 100, exit_price: 101,
      regime: "trending", strategy: "scalping", realized_pnl: 1.2
    )

    ai_payload = {
      strategies: {
        "scalping" => {
          "aggression_min" => 0.3,
          "aggression_max" => 0.7,
          "risk_min" => 0.8,
          "risk_max" => 1.2
        }
      },
      runtime: {
        "learning.epsilon" => 0.04,
        "risk.max_margin_utilization" => 0.38,
        "risk.daily_loss_cap_pct" => 0.045
      }
    }.to_json

    allow(Ai::OllamaClient).to receive(:ask).and_return(ai_payload)

    described_class.perform_now

    param = StrategyParam.find_by(strategy: "scalping", regime: "trending")
    expect(param.aggression.to_f).to be <= 0.7
    expect(param.risk_multiplier.to_f).to be <= 1.2
    expect(Setting.find_by(key: "learning.epsilon")&.typed_value).to eq(0.04)
    expect(Setting.find_by(key: "risk.max_margin_utilization")&.typed_value).to eq(0.38)
    changes = SettingChange.where(source: "ai_refinement_job")
    expect(changes.count).to be >= 2
    expect(changes.pluck(:reason).uniq).to eq(["auto_calibration"])
  end

  it "skips updates when payload is invalid JSON" do
    allow(Ai::OllamaClient).to receive(:ask).and_return("not-json")

    expect { described_class.perform_now }.not_to change(Setting, :count)
  end

  it "skips updates when payload root is not an object" do
    allow(Ai::OllamaClient).to receive(:ask).and_return([1, 2, 3].to_json)

    expect { described_class.perform_now }.not_to change(Setting, :count)
  end
end
