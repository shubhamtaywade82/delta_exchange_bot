# frozen_string_literal: true

module Api
  class OrderBlocksController < ApplicationController
    STRATEGY_KEY = "delta:strategy:state"

    def show
      symbol = params[:symbol]
      redis  = Redis.new
      raw    = redis.hget(STRATEGY_KEY, symbol)

      if raw
        state  = JSON.parse(raw, symbolize_names: true)
        blocks = state[:order_blocks] || []
        render json: { symbol: symbol, order_blocks: blocks }
      else
        render json: { symbol: symbol, order_blocks: [] }
      end
    rescue Redis::BaseError
      render json: { symbol: symbol, order_blocks: [] }
    end
  end
end
