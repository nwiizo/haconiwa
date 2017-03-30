module Haconiwa
  class WaitLoop
    def initialize
      @sig_threads = []
      @hook_threads = []
      @hooks = []
    end
    attr_reader :hooks

    def register_hooks(base)
      @hooks.each do |hook|
        hook.set_signal!
        proc = hook.proc
        @hook_threads << SignalThread.trap(hook.signal) do
          case proc.arity
          when 1
            proc.call(base)
          when 2
            proc.call(base, hook.active_timer)
          else
          end
        end
      end
    end

    def register_sighandlers(base, runner, etcd)
      [:SIGTERM, :SIGINT, :SIGHUP, :SIGPIPE].each do |sig|
        @sig_threads << SignalThread.trap(sig) do
          unless base.cleaned
            Logger.warning "Supervisor received unintended kill. Cleanup..."
            runner.cleanup_supervisor(base, etcd)
          end
          Process.kill :SIGTERM, base.pid
          exit 127
        end
      end
    end

    def register_custom_sighandlers(base, handlers)
      handlers.each do |sig, callback|
        @sig_threads << SignalThread.trap do |signo|
          callback.call(base)
        end
      end
    end

    def run_and_wait(pid)
      @hooks.each do |hook|
        hook.start
      end
      p, s = Process.waitpid2(pid)
      Logger.puts "Container(#{p}) finish detected: #{s.inspect}"
      return [p, s]
    end

    class TimerHook
      def self.signal_pool
        @__signal_pool = []
      end

      def initialize(timing={}, &b)
        @timing = if s = timing[:msec]
                    s
                  elsif s = timing[:sec]
                    s * 1000
                  elsif s = timing[:min]
                    s * 1000 * 60
                  elsif s = timing[:hour]
                    s * 1000 * 60 * 60
                  else
                    raise(ArgumentError, "Invalid option: #{timing.inspect}")
                  end
        @interval = timing[:interval_msec] # TODO: other time scales
        @proc = b
        @id = UUID.secure_uuid
        @signal = nil
        @active_timer = nil
      end
      attr_reader :timing, :proc, :id, :signal, :active_timer

      # This method has a race problem, should be called serially
      def set_signal!
        idx = 0
        while !signal do
          if TimerHook.signal_pool.include?(:"SIGRT#{idx}")
            idx += 1
          else
            @signal = :"SIGRT#{idx}"
            TimerHook.signal_pool << @signal
          end
        end
      end

      def start
        if signal
          t = ::Timer::POSIX.new(signal: signal)
          if @interval
            t.run(@timing, @interval)
          else
            t.run(@timing)
          end
          @active_timer = t
        end
      end
    end
  end
end
