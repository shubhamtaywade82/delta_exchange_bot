# frozen_string_literal: true

module Trading
  module Analysis
    # Heuristic entry / SL / TP ladder from 5m OB/FVG and 1h bias (not live orders).
    class TradePlanBuilder
      BUFFER_PCT = Float(ENV.fetch("ANALYSIS_TRADE_PLAN_BUFFER_PCT", "0.02"))

      def self.call(smc_by_timeframe:, last_price:, structure_bias:)
        new(
          smc_by_timeframe: smc_by_timeframe,
          last_price: last_price,
          structure_bias: structure_bias
        ).build
      end

      def initialize(smc_by_timeframe:, last_price:, structure_bias:)
        @tf = smc_by_timeframe.transform_keys(&:to_s)
        @price = last_price.to_f
        @bias = structure_bias.to_s
      end

      def build
        return none_plan("no_price") if @price <= 0

        direction = plan_direction
        return none_plan("no_clear_bias") if direction == :flat

        m5 = @tf["5m"]
        return none_plan("no_5m_smc") unless m5.is_a?(Hash) && m5["error"].blank?

        plan =
          if direction == :long
            long_plan_from(m5)
          else
            short_plan_from(m5)
          end
        return plan if plan[:direction] == "none"

        note = premium_discount_note(m5, direction)
        plan[:risk_reward_notes] = [plan[:risk_reward_notes], note].compact.join(" | ") if note
        plan
      end

      private

      def premium_discount_note(m5, direction)
        pd = m5["premium_discount"]
        return nil unless pd.is_a?(Hash)

        zone = pd["zone"].to_s
        if direction == :long && zone == "premium"
          "FILTER: 5m close in premium zone — long not ideal vs SMC discount rule."
        elsif direction == :short && zone == "discount"
          "FILTER: 5m close in discount zone — short not ideal vs SMC premium rule."
        end
      end

      def none_plan(reason)
        {
          direction: "none",
          reason: reason,
          entry: nil,
          stop_loss: nil,
          take_profit_1: nil,
          take_profit_2: nil,
          take_profit_3: nil,
          risk_reward_notes: nil
        }
      end

      def plan_direction
        case @bias
        when "bullish_aligned", "bullish"
          :long
        when "bearish_aligned", "bearish"
          :short
        else
          h1 = @tf["1h"]
          hint = h1.is_a?(Hash) ? h1["bias_hint"].to_s : ""
          case hint
          when "bullish" then :long
          when "bearish" then :short
          else :flat
          end
        end
      end

      def long_plan_from(m5)
        ob = pick_ob(m5, "bull")
        fvg = pick_fvg(m5, "bullish")
        entry = ob_entry(ob) || fvg_mid(fvg) || @price
        stop = ob_stop_long(ob) || fvg_stop_long(fvg) || buffer_stop(:long, entry)
        build_long_tp(entry, stop)
      end

      def short_plan_from(m5)
        ob = pick_ob(m5, "bear")
        fvg = pick_fvg(m5, "bearish")
        entry = ob_entry_short(ob) || fvg_mid(fvg) || @price
        stop = ob_stop_short(ob) || fvg_stop_short(fvg) || buffer_stop(:short, entry)
        build_short_tp(entry, stop)
      end

      def pick_ob(m5, side)
        list = m5["order_blocks"]
        return nil unless list.is_a?(Array)

        list.reverse.find { |o| o["side"] == side && o["fresh"] == true }
      end

      def pick_fvg(m5, type)
        list = m5["fair_value_gaps"]
        return nil unless list.is_a?(Array)

        list.reverse.find do |f|
          f["type"] == type && %w[unfilled partial].include?(f.dig("mitigation", "state"))
        end
      end

      def ob_entry(ob)
        return nil unless ob

        ((ob["high"].to_f + ob["low"].to_f) / 2.0)
      end

      def ob_entry_short(ob)
        ob_entry(ob)
      end

      def ob_stop_long(ob)
        return nil unless ob

        ob["low"].to_f - buffer_abs(ob["low"].to_f)
      end

      def ob_stop_short(ob)
        return nil unless ob

        ob["high"].to_f + buffer_abs(ob["high"].to_f)
      end

      def fvg_mid(fvg)
        return nil unless fvg

        ((fvg["high"].to_f + fvg["low"].to_f) / 2.0)
      end

      def fvg_stop_long(fvg)
        return nil unless fvg

        fvg["low"].to_f - buffer_abs(fvg["low"].to_f)
      end

      def fvg_stop_short(fvg)
        return nil unless fvg

        fvg["high"].to_f + buffer_abs(fvg["high"].to_f)
      end

      def buffer_abs(ref)
        ref.abs * (BUFFER_PCT / 100.0)
      end

      def buffer_stop(side, entry)
        buf = buffer_abs(entry)
        side == :long ? entry - buf : entry + buf
      end

      def build_long_tp(entry, stop)
        risk = entry - stop
        return none_plan("invalid_risk_long") if risk <= 0

        {
          direction: "long",
          reason: "heuristic_ob_fvg_structure",
          entry: entry,
          stop_loss: stop,
          take_profit_1: entry + risk,
          take_profit_2: entry + (2 * risk),
          take_profit_3: entry + (3 * risk),
          risk_reward_notes: "R multiples 1:1, 1:2, 1:3 vs planned risk #{risk.round(6)}"
        }
      end

      def build_short_tp(entry, stop)
        risk = stop - entry
        return none_plan("invalid_risk_short") if risk <= 0

        {
          direction: "short",
          reason: "heuristic_ob_fvg_structure",
          entry: entry,
          stop_loss: stop,
          take_profit_1: entry - risk,
          take_profit_2: entry - (2 * risk),
          take_profit_3: entry - (3 * risk),
          risk_reward_notes: "R multiples 1:1, 1:2, 1:3 vs planned risk #{risk.round(6)}"
        }
      end
    end
  end
end
