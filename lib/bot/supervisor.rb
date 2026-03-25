# frozen_string_literal: true

module Bot
  class Supervisor
    MAX_CRASHES      = 5
    CRASH_WINDOW_SEC = 600  # 10 minutes
    BACKOFF_SEQUENCE = [5, 10, 30, 60].freeze

    def initialize(logger:, notifier:)
      @logger   = logger
      @notifier = notifier
      @threads  = {}
      @stop     = false
    end

    def register(name, &block)
      @threads[name] = { block: block, crashes: [], thread: nil }
    end

    def start_all
      @threads.each_key { |name| spawn_thread(name) }
    end

    def monitor
      until @stop
        @threads.each do |name, meta|
          next if meta[:thread]&.alive?

          handle_crash(name)
        end
        sleep 5
      end
    end

    def stop_all
      @stop = true
      @threads.each_value { |meta| meta[:thread]&.kill }
    end

    private

    def spawn_thread(name)
      @threads[name][:thread] = Thread.new do
        @threads[name][:block].call
      rescue StandardError => e
        @logger.error("thread_crashed", thread: name.to_s, message: e.message,
                      backtrace: e.backtrace&.first(5)&.join(" | "))
      end
    end

    def handle_crash(name)
      meta = @threads[name]
      now  = Time.now.to_i

      # Prune old crash timestamps outside window
      meta[:crashes].select! { |t| now - t < CRASH_WINDOW_SEC }
      meta[:crashes] << now

      if meta[:crashes].size >= MAX_CRASHES
        msg = "🛑 #{name} crashed #{MAX_CRASHES} times in #{CRASH_WINDOW_SEC / 60}min. Bot halted."
        @logger.error("circuit_breaker_tripped", thread: name.to_s)
        @notifier.send_message(msg)
        stop_all
        exit 1
      end

      backoff = BACKOFF_SEQUENCE[[[meta[:crashes].size - 2, 0].max, BACKOFF_SEQUENCE.size - 1].min]
      attempt = meta[:crashes].size

      @logger.warn("thread_restarting", thread: name.to_s, backoff: backoff, attempt: attempt)
      @notifier.send_message("⚠️ #{name} crashed. Restarting in #{backoff}s... (attempt #{attempt}/#{MAX_CRASHES})")

      sleep backoff
      spawn_thread(name) unless @stop
    end
  end
end
