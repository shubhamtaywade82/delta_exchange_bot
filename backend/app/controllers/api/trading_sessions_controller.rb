# frozen_string_literal: true

module Api
  class TradingSessionsController < ApplicationController
    def index
      sessions = TradingSession.order(created_at: :desc).limit(20)
      render json: sessions
    end

    def create
      session = TradingSession.new(
        strategy: params[:strategy],
        status:   "running",
        capital:  params[:capital],
        leverage: params[:leverage]
      )

      if session.save
        DeltaTradingJob.perform_later(session.id)
        render json: { session_id: session.id, status: session.status }, status: :created
      else
        render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      session = TradingSession.find(params[:id])
      session.update!(status: "stopped", stopped_at: Time.current)

      client = DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
      Trading::KillSwitch.call(session.id, client: client)

      head :ok
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
