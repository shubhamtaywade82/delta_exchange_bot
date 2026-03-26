require 'rails_helper'

RSpec.describe "Api::Trades", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/api/trades/index"
      expect(response).to have_http_status(:success)
    end
  end

end
