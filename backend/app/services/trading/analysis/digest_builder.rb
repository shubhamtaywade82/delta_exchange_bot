# frozen_string_literal: true

module Trading
  module Analysis
    # Builds a JSON-serializable SMC / multi-timeframe digest for one symbol (BOS, order blocks, supertrend, ADX).
    class DigestBuilder
      SWING_LOOKBACK = Integer(ENV.fetch("ANALYSIS_BOS_SWING_LOOKBACK", "10"))
      OB_MIN_IMPULSE_PCT = Float(ENV.fetch("ANALYSIS_OB_MIN_IMPULSE_PCT", "0.3"))
      OB_MAX_AGE = Integer(ENV.fetch("ANALYSIS_OB_MAX_AGE", "20"))

      def self.call(symbol:, market_data:, config:)
        new(symbol: symbol, market_data: market_data, config: config).build
      end

      def initialize(symbol:, market_data:, config:)
        @symbol = symbol
        @market_data = market_data
        @config = config
      end

      def build
        trend = HistoricalCandles.fetch(market_data: @market_data, config: @config, symbol: @symbol,
                                          resolution: @config.timeframe_trend)
        confirm = HistoricalCandles.fetch(market_data: @market_data, config: @config, symbol: @symbol,
                                            resolution: @config.timeframe_confirm)
        entry = HistoricalCandles.fetch(market_data: @market_data, config: @config, symbol: @symbol,
                                          resolution: @config.timeframe_entry)

        required = @config.min_candles_required
        return insufficient(@symbol, :trend, trend.size, required) if trend.size < required
        return insufficient(@symbol, :confirm, confirm.size, required) if confirm.size < required
        return insufficient(@symbol, :entry, entry.size, required) if entry.size < required

        trend_st = Bot::Strategy::IndicatorFactory.compute_supertrend(trend, config: @config).last
        confirm_st = Bot::Strategy::IndicatorFactory.compute_supertrend(confirm, config: @config).last
        entry_st = Bot::Strategy::IndicatorFactory.compute_supertrend(entry, config: @config).last
        m15_adx = Bot::Strategy::ADX.compute(confirm, period: @config.adx_period).last

        bos_series = Bot::Strategy::Indicators::BOS.compute(entry, swing_lookback: SWING_LOOKBACK)
        bos = bos_series.last

        order_blocks = Bot::Strategy::Indicators::OrderBlock.compute(
          entry,
          min_impulse_pct: OB_MIN_IMPULSE_PCT,
          max_ob_age: OB_MAX_AGE
        )

        last_bar = entry.last
        ltp = Rails.cache.read("ltp:#{@symbol}")&.to_f
        last_close = last_bar[:close].to_f

        structure = structure_summary(trend_st, confirm_st, entry_st, m15_adx)
        insight = generate_ai_insight(structure, bos, order_blocks)

        {
          symbol: @symbol,
          error: nil,
          updated_at: Time.current.iso8601,
          ai_insight: insight,
          price_action: {
            last_close: round_price(last_close),
            ltp: ltp.positive? ? round_price(ltp) : nil,
            entry_timeframe: @config.timeframe_entry,
            last_bar_at: Time.zone.at(last_bar[:timestamp]).iso8601
          },
          market_structure: structure,
          timeframes: {
            trend: timeframe_digest(@config.timeframe_trend, trend, trend_st),
            confirm: timeframe_digest(@config.timeframe_confirm, confirm, confirm_st),
            entry: timeframe_digest(@config.timeframe_entry, entry, entry_st)
          },
          smc: {
            bos: {
              direction: bos[:direction]&.to_s,
              level: round_price(bos[:level]),
              confirmed: bos[:confirmed]
            },
            order_blocks: order_blocks.last(6).map { |ob| serialize_order_block(ob) }
          }
        }
      end

      private

      def generate_ai_insight(structure, bos, order_blocks)
        prompt = <<~TEXT
          You are a professional quant trading analysis agent. Provide exactly ONE punchy sentence summarizing the current technical regime for #{@symbol} based on this data:
          - Overall Bias: #{structure[:bias]} (H1: #{structure[:h1]}, M15: #{structure[:m15]}, M5: #{structure[:m5]})
          - ADX Strength: #{structure[:adx]} (#{structure[:trending] ? 'trending' : 'ranging'})
          - Entry BOS: #{bos ? "#{bos[:direction]} at #{round_price(bos[:level])}" : 'none'}
          - Closest #{order_blocks.size} Order Blocks: #{order_blocks.last(2).map{ |ob| "#{ob[:side]} at #{round_price(ob[:low])}-#{round_price(ob[:high])}" }.join(", ")}
          Do not hallucinate. Give only the analytical conclusion.
        TEXT

        Ai::OllamaClient.ask(prompt).strip.gsub(/\A"|"\Z/, "")
      rescue StandardError => e
        Rails.logger.warn("[DigestBuilder] AI insight failed for #{@symbol}: #{e.message}")
        nil
      end

      def insufficient(symbol, tf, got, need)
        {
          symbol: symbol,
          error: "insufficient_candles_#{tf}",
          candle_count: got,
          required: need,
          updated_at: Time.current.iso8601
        }
      end

      def round_price(value)
        return nil if value.nil?

        value.to_d.round(4).to_f
      end

      def serialize_order_block(ob)
        {
          side: ob[:side].to_s,
          high: round_price(ob[:high]),
          low: round_price(ob[:low]),
          age_bars: ob[:age],
          fresh: ob[:fresh],
          strength_pct: ob[:strength]
        }
      end

      def timeframe_digest(resolution, candles, st_last)
        last = candles.last
        {
          resolution: resolution,
          bars: candles.size,
          supertrend_direction: st_last[:direction]&.to_s,
          close: round_price(last[:close]),
          last_at: Time.zone.at(last[:timestamp]).iso8601
        }
      end

      def structure_summary(trend_st, confirm_st, entry_st, adx_row)
        h1 = trend_st[:direction]&.to_s
        m15 = confirm_st[:direction]&.to_s
        m5 = entry_st[:direction]&.to_s
        adx = adx_row[:adx]
        plus_di = adx_row[:plus_di]
        minus_di = adx_row[:minus_di]

        aligned_bull = h1 == "bullish" && m15 == "bullish" && m5 == "bullish"
        aligned_bear = h1 == "bearish" && m15 == "bearish" && m5 == "bearish"
        bias =
          if aligned_bull
            "bullish_aligned"
          elsif aligned_bear
            "bearish_aligned"
          else
            "mixed"
          end

        {
          bias: bias,
          h1: h1,
          m15: m15,
          m5: m5,
          adx: adx&.round(2),
          plus_di: plus_di&.round(2),
          minus_di: minus_di&.round(2),
          adx_threshold: @config.adx_threshold.to_f,
          trending: adx.present? && adx >= @config.adx_threshold
        }
      end
    end
  end
end
