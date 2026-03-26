class Api::PositionsController < ApplicationController
  def index
    render json: Position.where(status: "open")
  end
end
