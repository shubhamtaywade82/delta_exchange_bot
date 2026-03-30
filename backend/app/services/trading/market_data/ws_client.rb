# frozen_string_literal: true

module Trading
  module MarketData
    class WsClient
      def initialize(client:, symbols: nil, testnet: false)
        @client = client
        @symbols = symbols || SymbolConfig.where(enabled: true).pluck(:symbol)
        @testnet = testnet
        @price_store = Bot::Feed::PriceStore.new
        @recent_fill_ids = {}
        @recent_fill_queue = []
        @recent_fill_cache_size = ENV.fetch("WS_RECENT_FILL_CACHE_SIZE", 10_000).to_i
        @ingestion_queue = SizedQueue.new(ENV.fetch("WS_INGESTION_QUEUE_SIZE", 10_000).to_i)
        @worker_threads = []
        @metrics_mutex = Mutex.new
        @processed_count = 0
        @dropped_count = 0
        @last_metrics_at = Time.current
        @books = {}
      end

      def start
        start_workers

        loop do
          feed = Bot::Feed::WebsocketFeed.new(
            symbols: @symbols,
            price_store: @price_store,
            logger: Rails.logger,
            testnet: @testnet,
            on_tick: method(:handle_tick),
            on_message: method(:enqueue_message)
          )
          feed.start
          sleep reconnect_interval
        end
      rescue => e
        Rails.logger.error("[WsClient] Feed crashed: #{e.message}")
        raise
      end

      private

      def start_workers
        restart_missing_workers
        return if defined?(@worker_supervisor) && @worker_supervisor&.alive?

        @worker_supervisor = Thread.new do
          loop do
            restart_missing_workers
            emit_metrics_if_due
            sleep 1
          rescue => e
            Rails.logger.error("[WsClient] Worker supervisor crash: #{e.message}")
          end
        end
      end

      def restart_missing_workers
        worker_count = ENV.fetch("WS_INGESTION_WORKERS", 2).to_i

        @worker_threads.select!(&:alive?)
        (worker_count - @worker_threads.size).times do
          @worker_threads << Thread.new do
            loop do
              payload = @ingestion_queue.pop
              process_payload(payload)
              increment_processed
            rescue => e
              Rails.logger.error("[WsClient] Worker crash recovered: #{e.message}")
            end
          end
        end
      end

      def enqueue_message(payload)
        @ingestion_queue.push(payload, true)
      rescue ThreadError
        increment_dropped
        Rails.logger.warn("[WsClient] Ingestion queue full; dropping message")
      end

      def process_payload(payload)
        return unless payload.is_a?(Hash)

        case payload["type"]
        when "v2/fills"
          process_fill(payload)
        when "v2/orders"
          process_order(payload)
        when "v2/orderbook"
          on_orderbook_update(payload)
        end
      end

      def handle_tick(symbol, price, timestamp)
        Rails.cache.write("ltp:#{symbol}", price, expires_in: 30.seconds)
        evaluate_tick_risk(symbol: symbol, mark_price: price)

        EventBus.publish(
          :tick_received,
          Events::TickReceived.new(symbol: symbol, price: price, timestamp: timestamp, volume: 0.0)
        )
      end


      def evaluate_tick_risk(symbol:, mark_price:)
        portfolio = Trading::Risk::PortfolioSnapshot.current

        Position.active.where(symbol: symbol).find_each do |position|
          result = Trading::Risk::Engine.evaluate(position: position, mark_price: mark_price, portfolio: portfolio)
          Trading::Risk::Executor.handle!(position: position, signal: result[:liquidation], mark_price: mark_price)
        end
      end


      def on_orderbook_update(payload)
        symbol = payload["symbol"]
        return if symbol.blank?

        book = (@books[symbol] ||= Trading::Orderbook::Book.new)
        book.update!(
          bids: normalize_levels(payload["bids"]),
          asks: normalize_levels(payload["asks"])
        )

        trades = recent_trades_for(symbol)

        begin
          adaptive = Trading::AdaptiveEngine.tick(book: book, trades: trades, client: @client)
          Rails.cache.write("adaptive:entry_context:#{symbol}", adaptive, expires_in: 10.minutes)
        rescue => e
          Rails.logger.warn("[WsClient] Adaptive engine fallback: #{e.message}")
          signal = Trading::Microstructure::SignalEngine.call(book)
          decision = Trading::Execution::DecisionEngine.call(signal: signal, book: book)
          return if decision == :no_trade

          qty = ENV.fetch("MICROSTRUCTURE_ORDER_QTY", "1").to_d
          Trading::Execution::OrderRouter.place!(decision: decision, book: book, qty: qty, client: @client)
        end
      end


      def recent_trades_for(symbol)
        Fill.joins(:order)
            .where(orders: { symbol: symbol })
            .order(filled_at: :desc)
            .limit(ENV.fetch("ADAPTIVE_TRADE_WINDOW", 50).to_i)
            .to_a
            .reverse
      end

      def normalize_levels(levels)
        Array(levels).map do |entry|
          if entry.is_a?(Array)
            [entry[0], entry[1]]
          else
            [entry["price"], entry["size"]]
          end
        end
      end

      def process_fill(payload)
        fill_id = payload["fill_id"]&.to_s
        return if already_processed_fill?(fill_id)

        fill_event = Events::OrderFilled.new(
          exchange_fill_id: payload["fill_id"]&.to_s,
          exchange_order_id: payload["order_id"]&.to_s,
          client_order_id: payload["client_order_id"]&.to_s,
          symbol: payload["symbol"],
          side: payload["side"],
          quantity: payload["size"],
          price: payload["price"],
          fee: payload["fee"],
          filled_at: parse_time(payload["timestamp"]),
          status: payload["status"],
          raw_payload: payload
        )

        FillProcessor.process(fill_event)
      end

      def process_order(payload)
        order_event = Events::OrderUpdated.new(
          client_order_id: payload["client_order_id"]&.to_s,
          exchange_order_id: payload["id"]&.to_s,
          status: payload["status"],
          filled_qty: payload["filled_size"],
          avg_fill_price: payload["average_fill_price"],
          raw_payload: payload
        )

        OrderUpdater.process(order_event)
      end

      def already_processed_fill?(fill_id)
        return false if fill_id.blank?
        return true if @recent_fill_ids.key?(fill_id)

        @recent_fill_ids[fill_id] = true
        @recent_fill_queue << fill_id
        if @recent_fill_queue.size > @recent_fill_cache_size
          evicted = @recent_fill_queue.shift
          @recent_fill_ids.delete(evicted)
        end

        false
      end

      def increment_processed
        @metrics_mutex.synchronize { @processed_count += 1 }
      end

      def increment_dropped
        @metrics_mutex.synchronize { @dropped_count += 1 }
      end

      def emit_metrics_if_due
        interval = ENV.fetch("WS_METRICS_LOG_INTERVAL_SECONDS", 10).to_i
        return if (Time.current - @last_metrics_at) < interval

        processed, dropped = @metrics_mutex.synchronize { [@processed_count, @dropped_count] }
        Rails.logger.info("[WsClient] throughput processed=#{processed} dropped=#{dropped} queue=#{@ingestion_queue.size}")
        @last_metrics_at = Time.current
      end

      def parse_time(value)
        return Time.current if value.blank?

        Time.at(value.to_i)
      end

      def reconnect_interval
        base = ENV.fetch("WS_RECONNECT_BASE_SECONDS", 2).to_i
        jitter = rand(0.0..1.5)
        base + jitter
      end
    end
  end
end
