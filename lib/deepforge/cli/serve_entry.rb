#!/usr/bin/env ruby
# frozen_string_literal: true

#
# 文件用途：DeepForge CLI 的主入口脚本
# 功能说明：解析命令行参数，分发到 serve/main/agent 命令，并处理 serve 模式的启动握手和信号处理
# 使用方法：直接执行 ruby serve_entry.rb [command] [options]，或由外部脚本调用 DeepForge::CLI.main(ARGV)

require 'json'
require_relative 'serve'
require_relative 'agent_cli'

module DeepForge
  module CLI
    # GUI 启动握手的就绪前缀，用于标识运行时已准备好
    DEEPFORGE_READY_PREFIX = 'DEEPFORGE_READY '

    # 方法功能：serve 模式的主入口，启动 HTTP 服务并输出就绪信号
    # 参数：argv - 命令行参数数组
    # 返回值：整数退出码
    # 流程：解析参数 → 启动服务 → 输出 DEEPFORGE_READY 握手信息 → 等待 TERM/INT 信号关闭
    def self.serve_main(argv)
      if argv.empty? || argv.include?('--help') || argv.include?('-h')
        $stdout.write(SERVE_USAGE)
        return ServeExitCode::OK
      end

      parsed = parse_serve_options_safe(argv, ENV)
      unless parsed[:ok]
        $stderr.write("deepforge serve: #{parsed[:message]}\n")
        $stderr.write("#{JSON.pretty_generate(parsed[:issues])}\n") if parsed[:issues]
        return parsed[:exitCode]
      end

      handle = start_deepforge_serve(parsed[:options])
      info = handle[:runtime][:info].call
      startup_info = {
        service: 'deepforge',
        mode: 'serve',
        host: handle[:host],
        port: handle[:port],
        config_path: info[:configPath],
        data_dir: info[:dataDir],
        model: info[:model],
        approval_policy: info[:approvalPolicy],
        sandbox_mode: info[:sandboxMode],
        insecure: info[:insecure],
        started_at: info[:startedAt],
        pid: info[:pid],
        message: "deepforge runtime listening on http://#{handle[:host]}:#{handle[:port]}"
      }

      $stdout.write("#{DEEPFORGE_READY_PREFIX}#{JSON.generate(startup_info)}\n")
      $stdout.write("#{JSON.pretty_generate(startup_info)}\n")

      # Wait for shutdown signal
      %w[TERM INT].each do |signal|
        Signal.trap(signal) do
          handle[:close]&.call
          exit(ServeExitCode::OK)
        end
      end

      sleep # Wait indefinitely
      ServeExitCode::OK
    end

    # 方法功能：DeepForge CLI 的总入口，解析子命令并分发执行
    # 参数：argv - 命令行参数数组
    # 返回值：整数退出码
    def self.main(argv)
      command = split_deepforge_cli_command(argv)

      if command[:command] == :help
        if command[:error]
          $stderr.write("deepforge: #{command[:error]}\n")
          $stderr.write(AGENT_CLI_USAGE)
          return ServeExitCode::USAGE
        end
        $stdout.write(AGENT_CLI_USAGE)
        return ServeExitCode::OK
      end

      return serve_main(command[:args]) if command[:command] == :serve

      run_agent_command(command[:command], command[:args], {
                          stdin: $stdin,
                          stdout: $stdout,
                          stderr: $stderr,
                          env: ENV,
                          cwd: -> { Dir.pwd }
                        })
    end
  end
end

# 当脚本被直接执行时（非 require），自动调用 main 入口
if __FILE__ == $PROGRAM_NAME
  exit_code = DeepForge::CLI.main(ARGV)
  exit(exit_code)
end
