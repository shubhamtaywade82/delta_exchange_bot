class Api::TradesController < ApplicationController
  def index
    render json: Trade.order(closed_at: :desc).limit(100)
  end
end
