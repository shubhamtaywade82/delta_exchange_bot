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

        "trading_recommendation" (object):
          "primary_action" ("long"|"short"|"wait"),
          "conviction_0_to_100" (integer 0-100),
          "preferred_entry_model" ("ob_mitigation"|"fvg_mitigation"|"liquidity_sweep_follow_through"|"wait"|"none"),
          "entry_guidance" (string): zones/conditions from INPUT (no invented prices),
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
          - Prefer "wait" when INPUT shows conflicted bias, premium/discount mismatch, or missing mitigation.
          - Respect risk_and_execution_framework.min_suggested_rr conceptually when commenting on trade_plan.
          - trading_recommendation must be consistent with htf_bias and mtf_alignment unless you explain conflict in key_risks.

          #{SCHEMA_HINT}

          INPUT:
          #{JSON.generate(payload)}

          Output JSON only.
        PROMPT

        raw = Ai::OllamaClient.ask(prompt, connection_settings: connection_settings)
        parse_model_json(raw)
      rescue ::Timeout::Error
        log_ollama_timeout_hint(symbol)
        nil
      rescue StandardError => e
        if defined?(Ollama::TimeoutError) && e.is_a?(Ollama::TimeoutError)
          log_ollama_timeout_hint(symbol)
          return nil
        end

        Rails.logger.warn("[AiSmcSynthesizer] #{symbol}: #{e.message}")
        nil
      end

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
