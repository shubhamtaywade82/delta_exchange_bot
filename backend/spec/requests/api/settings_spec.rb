require 'rails_helper'

RSpec.describe "Api::Settings", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/api/settings/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/api/settings/update"
      expect(response).to have_http_status(:success)
    end
  end

end
