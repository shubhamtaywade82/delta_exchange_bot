# frozen_string_literal: true

require "timeout"

module Trading
  module Analysis
    # Sends full SMC JSON to Ollama; expects one JSON object with narrative + trading recommendation.
    class AiSmcSynthesizer
      SCHEMA_HINT = <<~TEXT.strip
        Return ONLY one JSON object (no markdown fences). Required top-level keys:

        "summary" (string): one tight paragraph tying HTF bias + liquidity + execution quality.
        "htf_bias" ("bullish"|"bearish"|"mixed"),
        "scenario" ("continuation"|"reversal"|"range"|"no_trade"),
        "confidence_0_to_100" (integer 0-100),
        "invalidation" (string): specific structure/level that voids the idea (use INPUT only),
        "takeaway_bullets" (array of strings, max 5),
        "comment_on_plan" (string): critique of heuristic trade_plan (risk, PD zone, alignment),
        "timeframe_notes" (object): optional strings for keys "5m","15m","1h",

        "long_trigger_conditions" (array of strings, max 4): specific conditions from INPUT that, if met NOW or soon, would justify a LONG entry (e.g. "BOS bullish confirmed on 15m + price returns to unfilled bullish FVG at 66,800-66,900 in discount zone"). Leave empty array if no plausible long setup exists.

        "short_trigger_conditions" (array of strings, max 4): specific conditions from INPUT that, if met NOW or soon, would justify a SHORT entry (e.g. "CHOCH bearish on 5m + sweep of equal highs near 67,200 with bearish OB mitigation"). Leave empty array if no plausible short setup exists.

        "trading_recommendation" (object):
          "primary_action" ("long"|"short"|"wait"),
          "conviction_0_to_100" (integer 0-100),
          "preferred_entry_model" ("ob_mitigation"|"fvg_mitigation"|"liquidity_sweep_follow_through"|"wait"|"none"),
          "entry_guidance" (string): zones/conditions from INPUT (no invented prices). Be specific about WHAT needs to happen for entry — not just "wait for confirmation",
          "structural_stop_guidance" (string),
          "target_guidance" (string or array of strings): next liquidity / RR framing,
          "aligns_with_htf_structure" (boolean),
          "premium_discount_compliance" (string): e.g. "long_ok_discount" / "long_avoid_premium",
          "liquidity_context" (string): EQH/EQL / sweep / session note from INPUT,
          "key_risks" (array of strings, max 4),
          "checklist" (array of strings, max 6): pass/fail style using INPUT flags only
      TEXT

      def self.call(symbol:, payload:, connection_settings: nil)
        prompt = <<~PROMPT
          You are an institutional-style SMC + price-action analyst. INPUT is machine-extracted from OHLCV; it is incomplete versus a full order-flow stack.

          Rules:
          - Do not invent prices, sessions, sweeps, or order flow not present in INPUT.
          - When bias is clear and structure supports it, commit to "long" or "short" with specific entry conditions.
          - Use "wait" only when bias is genuinely conflicted across timeframes, or the premium/discount zone strongly contradicts the direction.
          - Always provide both long_trigger_conditions and short_trigger_conditions so the trader knows what to watch for in EITHER direction, even if primary_action favors one side.
          - Respect risk_and_execution_framework.min_suggested_rr conceptually when commenting on trade_plan.
          - trading_recommendation must be consistent with htf_bias and mtf_alignment unless you explain conflict in key_risks.
          - entry_guidance must describe a concrete scenario, not vague "wait for confirmation."

          #{SCHEMA_HINT}

          INPUT:
          #{JSON.generate(payload)}

          Output JSON only.
        PROMPT

        raw = Ai::OllamaClient.ask(prompt, connection_settings: connection_settings)
        parse_model_json(raw)
      rescue ::Timeout::Error => e
        log_ollama_timeout_hint(symbol)
        HotPathErrorPolicy.log_swallowed_error(
          component: "Analysis::AiSmcSynthesizer",
          operation: "call",
          error:     e,
          log_level: :warn,
          symbol:    symbol,
          reason:    "ruby_timeout"
        )
        nil
      rescue StandardError => e
        log_ollama_timeout_hint(symbol) if ollama_client_timeout?(e)

        reason = ollama_client_timeout?(e) ? "ollama_timeout" : "error"
        HotPathErrorPolicy.log_swallowed_error(
          component: "Analysis::AiSmcSynthesizer",
          operation: "call",
          error:     e,
          log_level: :warn,
          symbol:    symbol,
          reason:    reason
        )
        nil
      end

      def self.ollama_client_timeout?(error)
        defined?(Ollama::TimeoutError) && error.is_a?(Ollama::TimeoutError)
      end
      private_class_method :ollama_client_timeout?

      def self.log_ollama_timeout_hint(symbol)
        Rails.logger.warn(
          "[AiSmcSynthesizer] #{symbol}: Ollama timed out (Ruby Timeout or HTTP read timeout). " \
          "Raise OLLAMA_TIMEOUT_SECONDS or settings key ai.ollama_timeout_seconds; " \
          "ensure `ollama serve` is up and the model is pulled (first run is slow on CPU)."
        )
      end

      def self.parse_model_json(raw)
        text = raw.to_s.strip
        text = Regexp.last_match(1).strip if text =~ /\A```(?:json)?\s*([\s\S]*?)```\z/m

        i = text.index("{")
        j = text.rindex("}")
        return nil unless i && j && j > i

        JSON.parse(text[i..j], symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
