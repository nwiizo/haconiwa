module Haconiwa
  class CRIUService
    def initialize(base)
      @base = base
    end

    def checkpoint
      @base.checkpoint
    end

    def create_checkpoint
      syscall = checkpoint.target_syscall
      if syscall.nil? || syscall.empty?
        Haconiwa::Logger.exception "Target systemcall not specified. Abort"
      end

      c = CRIU.new
      c.set_images_dir checkpoint.images_dir
      c.set_service_address checkpoint.criu_service_address
      c.set_log_file checkpoint.criu_log_file
      c.set_shell_job true

      pid = Process.fork do
        context = ::Seccomp.new(default: :allow) do |rule|
          rule.trace(*syscall)
        end
        context.load

        Dir.chdir ExpandPath.expand([@base.filesystem.chroot, @base.workdir].join('/'))
        Dir.chroot @base.filesystem.chroot
        Exec.execve(@base.environ, *@base.init_command)
      end

      ret = ::Seccomp.start_trace(pid) do |syscall, _pid, ud|
        name = ::Seccomp.syscall_to_name(syscall)
        Haconiwa::Logger.puts "CRIU: syscall #{name}(##{syscall}) called. (ud: #{ud}), dump the process image."

        begin
          c.set_pid _pid
          c.dump
        rescue => e
          Haconiwa::Logger.puts "CRIU: dump failed: #{e.class}, #{e.message}"
        else
          Haconiwa::Logger.puts "CRIU: dumped!!"
        end
      end
    end

    def restore
      # TODO: embed criu(crtools) to haconiwa...
      # Hooks won't work
      ::Exec.execve(ENV, "/usr/local/sbin/criu", "restore", "--shell-job", "-D", checkpoint.images_dir)
    end
  end
end
