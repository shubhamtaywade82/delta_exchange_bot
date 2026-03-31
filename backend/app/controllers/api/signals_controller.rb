# frozen_string_literal: true

module Api
  class SignalsController < ApplicationController
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500

    def index
      render json: recent_signals
    end

    private

    def recent_signals
      GeneratedSignal.order(created_at: :desc)
                     .limit(limit_param)
    end

    def limit_param
      requested = params[:limit].to_i
      return DEFAULT_LIMIT if requested <= 0

      [requested, MAX_LIMIT].min
    end
  end
end
