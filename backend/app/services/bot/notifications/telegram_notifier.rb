# frozen_string_literal: true

require "erb"
require "telegram/bot"

module Bot
  module Notifications
    class TelegramNotifier
      def initialize(enabled:, token:, chat_id:, logger: nil, event_settings: {})
        @enabled = enabled
        @token   = token
        @chat_id = chat_id.to_s
        @logger  = logger
        @event_settings = event_settings || {}
      end

      def send_message(text)
        return unless @enabled && !@token.to_s.empty?

        client.api.send_message(chat_id: @chat_id, text: text, parse_mode: "HTML")
      rescue StandardError => e
        log_send_failure(e.message)
      end

      private

      def log_send_failure(message)
        unless @logger
          $stderr.puts("[TelegramNotifier] Failed to send: #{message}")
          return
        end

        if @logger.is_a?(Bot::Notifications::Logger)
          @logger.error("telegram_send_failed", message: message)
        else
          @logger.error("[TelegramNotifier] telegram_send_failed: #{message}")
        end
      end

      def enabled_for?(event)
        return false unless @enabled && !@token.to_s.empty?
        return true unless @event_settings.key?(event.to_sym)

        @event_settings[event.to_sym] == true
      end

      def format_lots(n)
        x = n.to_f
        (x % 1.0).abs < 1e-9 ? x.to_i.to_s : format("%.4f", x).sub(/\.?0+\z/, "")
      end

      def client
        @client ||= Telegram::Bot::Client.new(@token)
      end

      public

      def notify_status(message, status: nil)
        return unless enabled_for?(:status)

        prefix = status ? "ℹ️ <b>#{status.upcase}</b>" : "ℹ️ <b>STATUS</b>"
        send_message("#{prefix}\n#{message}")
      end

      def notify_signal_generated(symbol:, side:, price:, strategy:)
        return unless enabled_for?(:signals)

        send_message("📡 <b>SIGNAL</b>\n#{symbol} #{side.to_s.upcase} via #{strategy}\nPrice: $#{format('%.2f', price)}")
      end

      # @param added_lots [Float, nil] contracts filled on this order; when prior net > 0, message is "scaled"
      def notify_trade_opened(symbol:, side:, price:, lots:, leverage:, trailing_stop:, mode:, added_lots: nil)
        return unless enabled_for?(:positions)

        emoji = side == :long ? "🟢" : "🔴"
        total = lots.to_f
        add = added_lots&.to_f
        prior = add.present? && add.positive? ? (total - add) : 0.0
        scaled = prior > 1e-6

        if scaled
          send_message(
            "#{emoji} <b>POSITION SCALED</b>\n" \
            "#{symbol} #{side.to_s.upcase} (#{mode})\n" \
            "Avg entry: $#{format('%.2f', price)}\n" \
            "+Lots this fill: #{format_lots(add)} | Total lots: #{format_lots(total)} | Leverage: #{leverage}x\n" \
            "Trail Stop: $#{format('%.2f', trailing_stop)}"
          )
        else
          send_message(
            "#{emoji} <b>POSITION OPENED</b>\n" \
            "#{symbol} #{side.to_s.upcase} (#{mode})\n" \
            "Entry: $#{format('%.2f', price)}\n" \
            "Lots: #{format_lots(total)} | Leverage: #{leverage}x\n" \
            "Trail Stop: $#{format('%.2f', trailing_stop)}"
          )
        end
      end

      def notify_trailing_stop_triggered(symbol:, side:, ltp:, stop_price:)
        return unless enabled_for?(:trailing)

        send_message(
          "🧷 <b>TRAILING STOP HIT</b>\n" \
          "#{symbol} #{side.to_s.upcase}\n" \
          "LTP: $#{format('%.2f', ltp)}\n" \
          "Stop: $#{format('%.2f', stop_price)}"
        )
      end

      def notify_trade_closed(symbol:, exit_price:, pnl_usd:, pnl_inr:, duration_seconds:, reason:, position_id: nil)
        return unless enabled_for?(:positions)

        sign  = pnl_usd >= 0 ? "+" : ""
        emoji = pnl_usd >= 0 ? "🟢" : "🔴"
        hours = duration_seconds / 3600
        mins  = (duration_seconds % 3600) / 60
        tail = position_id.present? ? "\n<code>position_id=#{position_id}</code>" : ""
        send_message(
          "#{emoji} <b>POSITION CLOSED</b>\n" \
          "#{symbol} — #{reason}\n" \
          "Exit: $#{format('%.2f', exit_price)}\n" \
          "PnL: #{sign}$#{format('%.2f', pnl_usd)} (#{sign}₹#{pnl_inr.round(0)})\n" \
          "Duration: #{hours}h #{mins}m#{tail}"
        )
      end

      def notify_error(context:, message:)
        return unless enabled_for?(:errors)

        send_message("🚨 <b>ERROR</b>\n#{context}\n#{message}")
      end

      # Plain-text SMC / Ollama summary from AnalysisDashboard digest; split across multiple Telegram messages.
      def notify_smc_analysis_digest(symbol:, plain_text:)
        return unless enabled_for?(:analysis)

        plain_text = plain_text.to_s.strip
        return if plain_text.empty?

        symbol_esc = ERB::Util.html_escape(symbol.to_s)
        body_limit = 3_800
        pieces = Bot::Notifications::TelegramTextChunker.chunk(plain_text, max_body_chars: body_limit)
        total = pieces.size

        pieces.each_with_index do |body, i|
          head = "🧠 <b>SMC ANALYSIS</b> #{symbol_esc}\n<code>#{i + 1}/#{total}</code>\n\n"
          send_message("#{head}#{ERB::Util.html_escape(body)}")
          sleep(0.06) if i < pieces.size - 1
        end
      end

      # Single-line SMC confluence event (Pine-style alert); uses +notifications.telegram.events.analysis+.
      # Optional +ai_insight+ is the Ollama +AiSmcSynthesizer+ summary (chunked when long), same family as digest pushes.
      def notify_smc_confluence_event(symbol:, title:, message_line:, ltp: nil, resolution: nil, ai_insight: nil)
        return unless enabled_for?(:analysis)

        symbol_esc = ERB::Util.html_escape(symbol.to_s)
        title_esc = ERB::Util.html_escape(title.to_s)
        line_esc = ERB::Util.html_escape(message_line.to_s)
        res_tail =
          if resolution.present?
            "\nTF: <code>#{ERB::Util.html_escape(resolution.to_s)}</code>"
          else
            ""
          end
        close_tail =
          if ltp.present? && ltp.to_d.positive?
            "\nClose: $#{format('%.2f', ltp.to_f)}"
          else
            ""
          end

        send_message("🔔 <b>#{title_esc}</b>\n#{symbol_esc}#{res_tail}\n#{line_esc}#{close_tail}")

        deliver_smc_event_ai_followup(symbol_esc: symbol_esc, plain_text: ai_insight)
      end

      private

      def deliver_smc_event_ai_followup(symbol_esc:, plain_text:)
        body = plain_text.to_s.strip
        return if body.empty?

        body_limit = 3_800
        pieces = Bot::Notifications::TelegramTextChunker.chunk(body, max_body_chars: body_limit)
        total = pieces.size

        pieces.each_with_index do |chunk, i|
          head = "🧠 <b>AI (SMC EVENT)</b> #{symbol_esc}\n<code>#{i + 1}/#{total}</code>\n\n"
          send_message("#{head}#{ERB::Util.html_escape(chunk)}")
          sleep(0.06) if i < pieces.size - 1
        end
      end
    end
  end
end
