# frozen_string_literal: true

module Api
  class ProductsController < ApplicationController
    def index
      # Fetch all products from Delta Exchange
      # Filter for Futures to keep the catalog focused
      all_products = DeltaExchange::Models::Product.all || []

      futures = all_products.select do |p|
        p.contract_type == "futures" || p.contract_type == "perpetual_futures"
      end

      # Enhance with current ticker info (OI, Mark Price) for the catalog view
      # Note: This might be slow if there are many products, so we only return basic info
      # and let the UI fetch specifics if needed, or we just return the symbols.

      render json: futures.map { |p|
        {
          symbol: p.symbol,
          description: p.description,
          contract_type: p.contract_type,
          tick_size: p.tick_size,
          quoting_asset: p.quoting_asset_symbol,
          underlying_asset: p.underlying_asset_symbol
        }
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :service_unavailable
    end
  end
end
