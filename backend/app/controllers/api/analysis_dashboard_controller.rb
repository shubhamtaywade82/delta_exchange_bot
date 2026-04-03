# frozen_string_literal: true

module Api
  class AnalysisDashboardController < ApplicationController
    def index
      render json: Trading::Analysis::Store.read
    end
  end
end
