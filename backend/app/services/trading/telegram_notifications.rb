# frozen_string_literal: true

module Trading
  # Bridges Bot::Config (DB-backed settings) to Bot::Notifications::TelegramNotifier for Trading::Runner.
  module TelegramNotifications
    module_function

    def notifier
      config = Bot::Config.load
      Bot::Notifications::TelegramNotifier.new(
        enabled: config.telegram_enabled?,
        token: config.telegram_token,
        chat_id: config.telegram_chat_id,
        logger: Rails.logger,
        event_settings: {
          status: config.telegram_event_enabled?(:status),
          signals: config.telegram_event_enabled?(:signals),
          positions: config.telegram_event_enabled?(:positions),
          trailing: config.telegram_event_enabled?(:trailing),
          errors: config.telegram_event_enabled?(:errors),
          analysis: config.telegram_event_enabled?(:analysis)
        }
      )
    end

    def deliver
      yield notifier
    rescue StandardError => e
      HotPathErrorPolicy.log_swallowed_error(
        component: "TelegramNotifications",
        operation: "deliver",
        error:     e,
        log_level: :warn
      )
    end
  end
end
