# frozen_string_literal: true

module Bot
  class Supervisor
    MAX_CRASHES      = 5
    CRASH_WINDOW_SEC = 600  # 10 minutes
    BACKOFF_SEQUENCE = [10, 30, 60, 300].freeze

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
      @threads.each do |name, meta|
        next if meta[:thread]&.alive?

        puts "CRASH DETECTED: #{name}"
        handle_crash(name)
      end
    end

    def stop_all
      @stop = true
      @threads.each_value { |meta| meta[:thread]&.kill }
    end

    private

    def backoff_for_attempt(attempt)
      # attempts 1 & 2 → first entry; each subsequent attempt advances one step; capped at last entry
      index = [[attempt - 2, 0].max, BACKOFF_SEQUENCE.size - 1].min
      BACKOFF_SEQUENCE[index]
    end

    def spawn_thread(name)
      puts "Spawning thread: #{name}"
      @threads[name][:thread] = Thread.new do
        @threads[name][:block].call
      rescue StandardError => e
        puts "THREAD ERROR [#{name}]: #{e.message}"
        puts e.backtrace.first(10).join("\n")
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

      attempt = meta[:crashes].size
      backoff = backoff_for_attempt(attempt)

      @logger.warn("thread_restarting", thread: name.to_s, backoff: backoff, attempt: attempt)
      @notifier.send_message("⚠️ #{name} crashed. Restarting in #{backoff}s... (attempt #{attempt}/#{MAX_CRASHES})")

      sleep backoff
      spawn_thread(name) unless @stop
    end
  end
end
