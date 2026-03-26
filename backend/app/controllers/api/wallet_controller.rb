# frozen_string_literal: true

module Api
  class WalletController < ApplicationController
    def index
      redis = Redis.new
      raw   = redis.get(Bot::Account::CapitalManager::REDIS_KEY)
      if raw
        render json: JSON.parse(raw)
      else
        render json: { available_usd: nil, available_inr: nil, capital_inr: nil,
                       paper_mode: true, updated_at: nil, stale: true }
      end
    rescue Redis::BaseError => e
      render json: { error: e.message }, status: :service_unavailable
    end
  end
end
