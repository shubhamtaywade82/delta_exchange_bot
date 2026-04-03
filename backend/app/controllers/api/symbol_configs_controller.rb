# frozen_string_literal: true

module Api
  class SymbolConfigsController < ApplicationController
    def index
      render json: SymbolConfig.all
    end

    def create
      raw = symbol_config_create_params
      symbol = raw[:symbol]
      unless symbol.present?
        render json: { error: "symbol is required" }, status: :unprocessable_content
        return
      end

      leverage = raw[:leverage].presence || 10
      enabled = raw.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(raw[:enabled]) : true
      product_id = raw[:product_id]

      config = SymbolConfig.find_or_initialize_by(symbol: symbol)
      config.update!(leverage: leverage, enabled: enabled, product_id: product_id)

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
      params.require(:symbol_config).permit(:leverage, :enabled, :product_id)
    end

    def symbol_config_create_params
      params.permit(:symbol, :leverage, :enabled, :product_id)
    end
  end
end
