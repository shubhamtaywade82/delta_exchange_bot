# frozen_string_literal: true

Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless ENV.fetch("ENABLE_SESSION_RESUMER", "true") == "true"

  resumed_count = Trading::SessionResumer.call
  Rails.logger.info("[SessionResumer] resumed #{resumed_count} running sessions")
end
