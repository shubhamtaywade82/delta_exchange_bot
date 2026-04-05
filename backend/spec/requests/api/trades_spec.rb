require 'rails_helper'

RSpec.describe "Api::Trades", type: :request do
  describe "GET /api/trades" do
    it "returns http success" do
      get "/api/trades"
      expect(response).to have_http_status(:success)
    end
  end
end
