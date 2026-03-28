# frozen_string_literal: true

module Api
  class SymbolConfigsController < ApplicationController
    def index
      render json: SymbolConfig.all
    end

    def create
      # Add or update a symbol in the watchlist
      symbol   = params[:symbol]
      leverage = params[:leverage] || 10
      enabled  = params[:enabled] != false

      config = SymbolConfig.find_or_initialize_by(symbol: symbol)
      config.update!(leverage: leverage, enabled: enabled)

      render json: config
    end

    def update
      config = SymbolConfig.find(params[:id])
      config.update!(symbol_config_params)
      render json: config
    end

    def destroy
      # Usually we just disable, but we can also delete if requested.
      # For the catalog, we'll just toggle 'enabled' to false if it's already there
      # or remove it if requested.
      config = SymbolConfig.find_by(id: params[:id]) || SymbolConfig.find_by(symbol: params[:id])
      
      if config
        config.update!(enabled: false)
        render json: { success: true, message: "Removed #{config.symbol} from watchlist" }
      else
        render json: { error: "Symbol not found in watchlist" }, status: :not_found
      end
    end

    private

    def symbol_config_params
      params.require(:symbol_config).permit(:leverage, :enabled)
    end
  end
end
