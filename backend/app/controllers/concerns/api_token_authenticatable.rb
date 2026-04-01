# frozen_string_literal: true

# When API_ACCESS_TOKEN is set, all JSON API requests must send the same value as
#   Authorization: Bearer <token>   or   X-Api-Token: <token>
# Leave unset in local dev; set in any environment where the API is reachable beyond localhost.
module ApiTokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :verify_api_access_token, if: :api_access_token_configured?
  end

  private

  def api_access_token_configured?
    ENV["API_ACCESS_TOKEN"].to_s.present?
  end

  def verify_api_access_token
    expected = ENV["API_ACCESS_TOKEN"].to_s
    candidate = provided_api_token.to_s
    unless timing_safe_equal?(candidate, expected)
      head :unauthorized
    end
  end

  def provided_api_token
    header = request.headers["Authorization"].to_s
    if (m = header.match(/\ABearer\s+(.+)\z/i))
      return m[1].strip
    end

    request.headers["X-Api-Token"].to_s.presence
  end

  def timing_safe_equal?(a, b)
    return false if a.bytesize != b.bytesize

    ActiveSupport::SecurityUtils.secure_compare(a, b)
  end
end
