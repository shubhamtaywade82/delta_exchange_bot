# frozen_string_literal: true

module Trading
  module Dashboard
    # Closes one active position from the dashboard (paper: synthetic mark; live: market + DB close).
    class ManualPositionClose
      Result = Struct.new(:ok, :http_status, :error, :position_id, keyword_init: true)

      def self.call(position_id:)
        pid = position_id.to_i
        return Result.new(ok: false, http_status: :bad_request, error: "invalid_position_id") if pid <= 0

        position = Position.active.find_by(id: pid)
        return Result.new(ok: false, http_status: :not_found, error: "position_not_found") unless position

        running = resolve_running_session
        unless authorized?(position, running)
          return Result.new(ok: false, http_status: :forbidden, error: "position_not_allowed_for_session")
        end

        client = delta_client_for_close
        return Result.new(ok: false, http_status: :unprocessable_content, error: "delta_credentials_missing") if client == :missing

        EmergencyShutdown.force_exit_position(position, client, reason: "MANUAL_DASHBOARD_CLOSE")
        Result.new(ok: true, http_status: :ok, error: nil, position_id: pid)
      rescue StandardError => e
        Rails.logger.error("[ManualPositionClose] #{e.class}: #{e.message}")
        Result.new(ok: false, http_status: :internal_server_error, error: "close_failed")
      end

      def self.resolve_running_session
        TradingSession.where(status: "running")
                      .order(Arel.sql("COALESCE(started_at, created_at) DESC NULLS LAST"), id: :desc)
                      .first
      end

      def self.authorized?(position, running_session)
        if PaperTrading.enabled?
          return false unless running_session&.portfolio_id.present?

          return position.portfolio_id == running_session.portfolio_id
        end

        true
      end

      def self.delta_client_for_close
        return nil if PaperTrading.enabled?

        return :missing unless delta_credentials_present?

        DeltaExchange::Client.new(
          api_key:    ENV.fetch("DELTA_API_KEY"),
          api_secret: ENV.fetch("DELTA_API_SECRET")
        )
      end

      def self.delta_credentials_present?
        ENV["DELTA_API_KEY"].to_s.strip.present? && ENV["DELTA_API_SECRET"].to_s.strip.present?
      end
      private_class_method :delta_credentials_present?
    end
  end
end
