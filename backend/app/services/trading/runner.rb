# frozen_string_literal: true

module Trading
  class Runner
    def initialize(session_id:, client: nil)
      @session = TradingSession.find(session_id)
      @client  = client || build_client
      @running = true
    end

    def start
      Rails.logger.info("[Runner] Starting session #{@session.id} strategy=#{@session.strategy}")
      bootstrap!
      register_event_handlers!
      seed_candle_series!
      start_ws!
      run_loop
    ensure
      EventBus.reset!
      Rails.logger.info("[Runner] Session #{@session.id} exited cleanly")
    end

    def stop
      @running = false
    end

    private

    def bootstrap!
      Bootstrap::SyncPositions.call(client: @client)
      Bootstrap::SyncOrders.call(client: @client, session: @session)
    end

    def register_event_handlers!
      EventBus.subscribe(:candle_closed) do |candle|
        Handlers::TickHandler.new(candle, @session, @client).call
      end
      EventBus.subscribe(:order_filled) do |event|
        Handlers::OrderHandler.new(event).call
      end
      EventBus.subscribe(:position_updated) do |event|
        Handlers::PositionHandler.new(event).call
      end
    end

    def seed_candle_series!
      symbols = SymbolConfig.where(enabled: true).pluck(:symbol)
      fetcher = MarketData::OhlcvFetcher.new(client: @client)
      symbols.each do |symbol|
        candles = fetcher.fetch(symbol: symbol, resolution: "1m", limit: 200)
        MarketData::CandleSeries.load(candles)
        Rails.logger.info("[Runner] Seeded #{candles.size} candles for #{symbol}")
      end
    end

    def start_ws!
      symbols  = SymbolConfig.where(enabled: true).pluck(:symbol)
      testnet  = @session.strategy.include?("testnet") || ENV["DELTA_TESTNET"] == "true"

      @ws_thread = Thread.new do
        MarketData::WsClient.new(client: @client, symbols: symbols, testnet: testnet).start
      rescue => e
        Rails.logger.error("[Runner] WS thread crashed: #{e.message}")
      end
    end

    def run_loop
      while running?
        LiquidationGuard.check_all(client: @client)
        FundingMonitor.check_all(client: @client)
        sleep 5
      end
    end

    def running?
      @running && @session.reload.running?
    rescue ActiveRecord::RecordNotFound
      false
    end

    def build_client
      DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
    end
  end
end
