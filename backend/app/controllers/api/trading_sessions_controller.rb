# frozen_string_literal: true

module Api
  class TradingSessionsController < ApplicationController
    def index
      base = TradingSession.order(created_at: :desc)
      if paginate_index?
        page = index_page_param
        per_page = index_per_page_param
        total = base.count
        rows = base.offset((page - 1) * per_page).limit(per_page)
        render json: {
          sessions: rows,
          meta: { page: page, per_page: per_page, total: total }
        }
      else
        render json: base.limit(20)
      end
    end

    def create
      session = TradingSession.new(trading_session_attributes)
      session.status = "running"

      if session.save
        DeltaTradingJob.perform_later(session.id)
        render json: { session_id: session.id, status: session.status }, status: :created
      else
        render json: { errors: session.errors.full_messages }, status: :unprocessable_content
      end
    end

    def destroy
      session = TradingSession.find(params[:id])
      was_running = session.running?
      if was_running
        session.update!(status: "stopped", stopped_at: Time.current)
        run_emergency_shutdown_if_possible(session)
      end

      head :ok
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def run_emergency_shutdown_if_possible(session)
      unless delta_credentials_present?
        Rails.logger.warn(
          "[TradingSessionsController] Delta API credentials missing; emergency shutdown skipped " \
          "session_id=#{session.id}"
        )
        return
      end

      client = DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
      Trading::EmergencyShutdown.call(session.id, client: client)
    rescue StandardError => e
      Rails.logger.error(
        "[TradingSessionsController] EmergencyShutdown failed session_id=#{session.id}: " \
        "#{e.class}: #{e.message}"
      )
    end

    def paginate_index?
      params[:page].present? || params[:per_page].present?
    end

    def index_page_param
      p = params[:page].to_i
      p.positive? ? p : 1
    end

    def index_per_page_param
      raw = params[:per_page].to_i
      raw = 20 if raw <= 0
      [raw, 100].min
    end

    def trading_session_attributes
      if params[:trading_session].present?
        params.require(:trading_session).permit(:strategy, :capital, :leverage)
      else
        params.permit(:strategy, :capital, :leverage)
      end
    end

    def delta_credentials_present?
      ENV["DELTA_API_KEY"].to_s.strip.present? && ENV["DELTA_API_SECRET"].to_s.strip.present?
    end
  end
end
