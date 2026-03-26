require 'rails_helper'

RSpec.describe "Api::Dashboards", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/api/dashboard/index"
      expect(response).to have_http_status(:success)
    end
  end

end
