require 'rails_helper'

RSpec.describe "Api::Positions", type: :request do
  describe "GET /api/positions" do
    it "returns http success" do
      get "/api/positions"
      expect(response).to have_http_status(:success)
    end
  end
end
