# frozen_string_literal: true

module Trading
  # Shared Delta REST client construction for Runner, async jobs, and scripts.
  module RunnerClient
    module_function

    def build
      if PaperTrading.enabled?
        key    = ENV["DELTA_API_KEY"].to_s
        secret = ENV["DELTA_API_SECRET"].to_s
        return DeltaExchange::Client.new(api_key: key.presence, api_secret: secret.presence)
      end

      DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
    end
  end
end
