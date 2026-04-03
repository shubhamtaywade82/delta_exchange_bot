# frozen_string_literal: true

module Trading
  # RuntimeConfig provides DB-backed live config with short cache TTL.
  class RuntimeConfig
    CACHE_TTL_SECONDS = 5

    class << self
      def fetch_string(key, default: nil, env_key: nil)
        value = fetch(key, env_key: env_key, default: default)
        value.nil? ? default : value.to_s
      end

      def fetch_integer(key, default:, env_key: nil)
        value = fetch(key, env_key: env_key, default: default)
        Integer(value)
      rescue ArgumentError, TypeError
        default
      end

      def fetch_float(key, default:, env_key: nil)
        value = fetch(key, env_key: env_key, default: default)
        Float(value)
      rescue ArgumentError, TypeError
        default
      end

      def fetch_boolean(key, default:, env_key: nil)
        value = fetch(key, env_key: env_key, default: default)
        return value if value == true || value == false

        value.to_s.strip.downcase.in?(%w[1 true yes on])
      rescue StandardError
        default
      end

      def refresh!(key = nil)
        return Rails.cache.delete(cache_key(key)) if key.present?

        Rails.cache.delete_matched("runtime_config:*")
      rescue NotImplementedError
        nil
      end

      private

      def fetch(key, env_key:, default:)
        Rails.cache.fetch(cache_key(key), expires_in: CACHE_TTL_SECONDS.seconds) do
          read_from_db(key) || read_from_env(env_key || key) || default
        end
      end

      def read_from_db(key)
        Setting.find_by(key: key)&.typed_value
      end

      def read_from_env(key)
        ENV[key]
      end

      def cache_key(key)
        "runtime_config:#{key}"
      end
    end
  end
end
