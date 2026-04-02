# frozen_string_literal: true

module Trading
  module Positions
    # Compares stored entry (VWAP from fills) and first-fill price to the 1m candle **close**
    # for the minute containing the first fill's +filled_at+.
    #
    # Delta /v2/history/candles returns +time+ (mapped to +:timestamp+ by HistoricalCandles). That value may be
    # period open or period end; we match both. Epochs may be seconds or milliseconds.
    #
    # Caveats:
    # - +entry_price+ is VWAP across all opening fills; comparing VWAP to one 1m close is misleading when +fill_count+ > 1.
    #   +ok+ uses first-fill vs close for those rows; +diff_entry_vs_close_pct+ remains for inspection only.
    # - Market / paper fills use mark or last trade; the official 1m close is the last print in that minute — not identical.
    # - +created_at+ / +updated_at+ on +Position+ are row lifecycle times; they do not define the fill price.
    # - Open rows: fill set matches +PositionRecalculator+ — all fills for +(portfolio_id, symbol)+.
    # - Closed / liquidated: fills for +(portfolio_id, symbol, position_id)+ so later cycles on the same symbol do not mix in.
    class EntryOneMinuteSanity
      ONE_MINUTE = 60
      WINDOW_SECONDS = 600
      WIDE_WINDOW_SECONDS = 86_400

      ResultRow = Struct.new(
        :position_id,
        :symbol,
        :status,
        :entry_price,
        :first_fill_at,
        :first_fill_price,
        :fill_count,
        :candle_open_ts,
        :candle_close,
        :diff_entry_vs_close_pct,
        :diff_first_fill_vs_close_pct,
        :ok,
        :note,
        keyword_init: true
      )

      def self.call(positions: nil, tolerance_pct: 0.25, market_data: nil)
        new(
          positions: positions || default_positions_scope,
          tolerance_pct: tolerance_pct,
          market_data: market_data || build_default_market_data
        ).call
      end

      # Mirrors Position.active plus settled rows (historical trades) for the same entry/fill sanity check.
      ENTRY_CHECK_STATUSES = %w[
        entry_pending partially_filled filled exit_pending open closed liquidated
      ].freeze

      TERMINAL_STATUSES = %w[closed liquidated].freeze

      # Single-fill rows: +entry_price+ must be near the one fill price; above this rel error, +ok+ is false even if
      # first fill vs 1m close looks fine (stored entry is misleading). Looser than the note threshold below.
      ENTRY_VS_FIRST_OK_MAX_REL = BigDecimal("0.001")

      def self.default_positions_scope
        Position.where(status: ENTRY_CHECK_STATUSES)
                .where.not(entry_price: nil)
                .order(:id)
      end

      def self.build_default_market_data
        Trading::RunnerClient.build.market_data
      end

      def initialize(positions:, tolerance_pct:, market_data:)
        @positions = positions
        @tolerance_pct = tolerance_pct.to_f
        @market_data = market_data
      end

      def call
        list = @positions.respond_to?(:to_a) ? @positions.to_a : Array(@positions)
        return [] if list.empty?

        fills_index = build_fills_index(list)
        list.map { |p| row_for(p, fills_index) }.compact
      end

      private

      def row_for(position, fills_index)
        fills = fills_for_position(position, fills_index)
        return nil if fills.empty?

        first = fills.min_by { |f| [ f.filled_at, f.id ] }
        anchor = first.filled_at
        return nil if anchor.blank?

        bars = fetch_1m_bars(position.symbol.to_s, anchor)
        bar = bar_containing(bars, anchor)
        return missing_bar_row(position, first, fills.size, bars.size) if bar.nil?

        close = bar[:close].to_d
        return nil if close.zero?

        entry = position.entry_price.to_d
        first_px = first.price.to_d
        diff_entry_pct = pct_abs_diff(entry, close)
        diff_first_pct = pct_abs_diff(first_px, close)
        ok = row_ok?(fills, position, first, diff_first_pct)

        note = note_for(fills, position, first)

        ResultRow.new(
          position_id: position.id,
          symbol: position.symbol,
          status: position.status,
          entry_price: entry.to_f,
          first_fill_at: anchor.iso8601,
          first_fill_price: first_px.to_f,
          fill_count: fills.size,
          candle_open_ts: bar[:timestamp],
          candle_close: close.to_f,
          diff_entry_vs_close_pct: diff_entry_pct.round(4),
          diff_first_fill_vs_close_pct: diff_first_pct.round(4),
          ok: ok,
          note: note
        )
      end

      def row_ok?(fills, position, first, diff_first_pct)
        return false if diff_first_pct > @tolerance_pct

        return true if fills.size > 1

        single_fill_entry_aligned_for_ok?(position, first)
      end

      def single_fill_entry_aligned_for_ok?(position, first)
        e = position.entry_price.to_d
        p = first.price.to_d
        return true if e.blank? || p.blank? || p.zero?

        rel = (e - p).abs / p.abs
        rel < ENTRY_VS_FIRST_OK_MAX_REL
      end

      def note_for(fills, position, first)
        if fills.size > 1
          return "VWAP over #{fills.size} fills (ledger scope) — entry may diverge from one 1m close."
        end

        return if fills.size != 1

        e = position.entry_price.to_d
        p = first.price.to_d
        return if e.blank? || p.blank? || p.zero?

        rel = (e - p).abs / p.abs
        return if rel < BigDecimal("1e-8")

        "Single fill but entry_price != that fill (#{rel.round(8)} rel); run bin/rails trading:reconcile_positions."
      end

      # One query batch for terminal positions (+position_id+), one OR-combined query for open (+portfolio_id+, +symbol+).
      def build_fills_index(list)
        index = {}
        terminal = list.select { |p| TERMINAL_STATUSES.include?(p.status.to_s) }
        open = list.reject { |p| TERMINAL_STATUSES.include?(p.status.to_s) }

        if terminal.any?
          ids = terminal.map(&:id).uniq
          Fill.joins(:order)
              .where(orders: { position_id: ids })
              .includes(:order)
              .to_a
              .group_by { |f| f.order.position_id }
              .each { |pid, arr| index[[ :terminal, pid ]] = arr }
        end

        if open.any?
          keys = open.map { |p| [ p.portfolio_id, p.symbol.to_s ] }.uniq
          fills_scope_for_open_keys(keys).includes(:order).to_a
            .group_by { |f| [ f.order.portfolio_id, f.order.symbol.to_s ] }
            .each { |k, arr| index[[ :open, k[0], k[1] ]] = arr }
        end

        index
      end

      def fills_scope_for_open_keys(keys)
        return Fill.none if keys.empty?

        rels = keys.map do |portfolio_id, symbol|
          Fill.joins(:order).where(orders: { portfolio_id: portfolio_id, symbol: symbol })
        end
        rels.reduce { |acc, r| acc.or(r) }
      end

      def fills_for_position(position, index)
        if TERMINAL_STATUSES.include?(position.status.to_s)
          index[[ :terminal, position.id ]] || []
        else
          index[[ :open, position.portfolio_id, position.symbol.to_s ]] || []
        end
      end

      def fetch_1m_bars(symbol, anchor)
        center = anchor.to_i
        bars = candles_in_window(symbol, center, WINDOW_SECONDS)
        return bars if bars.any?

        candles_in_window(symbol, center, WIDE_WINDOW_SECONDS)
      end

      def candles_in_window(symbol, center, half_span)
        raw = @market_data.candles(
          "symbol" => symbol,
          "resolution" => "1m",
          "start" => center - half_span,
          "end" => center + half_span
        )
        rows = Trading::Analysis::HistoricalCandles.normalize_candles(raw)
        rows.each { |c| c[:timestamp] = epoch_seconds(c[:timestamp]) }
        rows.sort_by! { |c| c[:timestamp].to_i }
      end

      def bar_containing(bars, anchor)
        t = epoch_seconds(anchor.to_i)
        return nil if t <= 0

        bars.find { |c| bar_covers_fill?(epoch_seconds(c[:timestamp]), t) }
      end

      def bar_covers_fill?(bar_ts, fill_ts)
        return false if bar_ts <= 0

        open_aligned = fill_ts >= bar_ts && fill_ts < bar_ts + ONE_MINUTE
        return true if open_aligned

        close_aligned = fill_ts > bar_ts - ONE_MINUTE && fill_ts <= bar_ts
        close_aligned
      end

      def epoch_seconds(value)
        n = value.to_i
        return 0 if n <= 0

        n >= 10_000_000_000 ? n / 1000 : n
      end

      def pct_abs_diff(a, b)
        return 0.0 if b.zero?

        ((a - b).abs / b.abs * 100).to_f
      end

      def missing_bar_row(position, first, fill_count, bars_returned)
        hint =
          if bars_returned.zero?
            "REST returned no 1m rows (symbol/host, rate limit, or window)."
          else
            "Could not place fill in any returned bar (epoch ms vs s, or non-standard bar clock)."
          end

        ResultRow.new(
          position_id: position.id,
          symbol: position.symbol,
          status: position.status,
          entry_price: position.entry_price.to_f,
          first_fill_at: first.filled_at.iso8601,
          first_fill_price: first.price.to_f,
          fill_count: fill_count,
          candle_open_ts: nil,
          candle_close: nil,
          diff_entry_vs_close_pct: nil,
          diff_first_fill_vs_close_pct: nil,
          ok: false,
          note: "No 1m bar matched first fill time (#{hint}; bars_in_window=#{bars_returned})."
        )
      end
    end
  end
end
