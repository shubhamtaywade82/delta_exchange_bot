# frozen_string_literal: true

class Api::DashboardController < ApplicationController
  def index
    q = params.permit(:calendar_day, :trades_day, :trades_limit)
    render json: Trading::Dashboard::Snapshot.call(
      calendar_day: q[:calendar_day],
      trades_day: q[:trades_day],
      trades_limit: q[:trades_limit]
    )
  end

  # Paper mode only: toggle `paper.ignore_entry_risk_gates` so RiskManager + PortfolioGuard gates are skipped for testing.
  def paper_risk_override
    unless Trading::PaperTrading.enabled?
      render json: { error: "paper_risk_override_requires_paper_mode" }, status: :unprocessable_content
      return
    end

    flag = params.permit(:ignore_entry_risk_gates).require(:ignore_entry_risk_gates)
    enabled = ActiveModel::Type::Boolean.new.cast(flag)
    Trading::PaperRiskOverride.set!(enabled: enabled)
    render json: { paper_risk_override_active: Trading::PaperRiskOverride.active? }
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
