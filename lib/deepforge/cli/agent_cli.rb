# frozen_string_literal: true

#
# 文件用途：DeepForge Agent CLI 命令行接口实现
# 功能说明：提供 serve（启动服务）、run（单次执行）、chat（交互对话）、exec（直接调用工具）四个子命令
# 使用方法：通过 deepforge.rb 入口调用 DeepForge::CLI.main(ARGV)，自动分发到对应子命令

require 'json'
require 'io/console'
require_relative 'serve'

module DeepForge
  module CLI
    # CLI 使用说明文本，用于 --help 输出
    AGENT_CLI_USAGE = <<~USAGE
      deepforge <command> [options]

      Commands:
        serve [options]            Start the local HTTP/SSE runtime
        run [options] <prompt>     Run one agent turn without the GUI
        chat [options]             Start a line-oriented terminal chat
        exec [options] <tool>      List or invoke tools directly

      Common options:
        --config <path>            JSON config file
        --data-dir <path>          Root directory for DeepForge data
        --workspace <path>         Workspace root for run/chat/exec
        --model <model>            Model id
        --approval-policy <p>      on-request | untrusted | never | auto | suggest
        --json                     Emit machine-readable JSON where supported

      Exec options:
        --list-tools               Print available tools
        --args <json>              JSON object passed to the selected tool
    USAGE

    # 需要后跟值的命令行标志列表
    VALUE_FLAGS = %w[
      config config-file host port data-dir dataDir runtime-token runtimeToken
      api-key apiKey base-url baseUrl model approval-policy sandbox-mode
      workspace prompt p args title
    ].freeze

    # CLI 支持的命令类型枚举
    CLI_COMMANDS = %i[serve run chat exec help].freeze

    # 方法功能：从命令行参数中解析出子命令类型和剩余参数
    # 参数：argv - 命令行参数数组
    # 返回值：Hash，包含 :command（符号）、:args（数组）、可选 :error（错误信息）
    # 使用方法：split_deepforge_cli_command(['run', '--model', 'gpt-4']) => { command: :run, args: ['--model', 'gpt-4'] }
    def self.split_deepforge_cli_command(argv)
      first = argv[0]

      return { command: :help, args: [] } if first.nil? || first == '--help' || first == '-h' || first == 'help'

      return { command: first.to_sym, args: argv[1..] } if %w[serve run chat exec].include?(first)

      return { command: :serve, args: argv.dup } if first.start_with?('--')

      { command: :help, args: [], error: "unknown command: #{first}" }
    end

    # 方法功能：根据命令类型分发执行对应子命令
    # 参数：command - 命令符号（:run / :chat / :exec）；argv - 命令行参数；io - IO 流哈希
    # 返回值：整数退出码
    def self.run_agent_command(command, argv, io)
      case command
      when :run
        run_one_shot(argv, io)
      when :chat
        run_chat(argv, io)
      when :exec
        run_exec(argv, io)
      else
        io[:stderr].write("Unknown command: #{command}\n")
        ServeExitCode::USAGE
      end
    end

    # 方法功能：执行一次性的 Agent 对话轮次（非交互模式）
    # 参数：argv - 命令行参数；io - IO 流哈希（含 stdin/stdout/stderr）
    # 返回值：整数退出码（0 成功，70 运行时错误，64 参数错误）
    # 使用方法：deepforge run "请帮我写一个函数" --model deepseek-chat
    def self.run_one_shot(argv, io)
      parsed = parse_shared_options(argv, io)
      return write_parse_error(parsed, io, 'deepforge run') unless parsed[:ok]

      prompt = string_flag(argv, %w[prompt p]) || positionals(argv).join(' ').strip
      unless prompt
        io[:stderr].write("deepforge run: missing prompt\n")
        return ServeExitCode::USAGE
      end

      runtime = nil
      begin
        runtime = create_runtime(parsed[:options], io)
        thread = runtime[:thread_service].create(
          title: string_flag(argv, ['title']) || prompt[0..79],
          workspace: parsed[:workspace],
          model: parsed[:options].model,
          mode: 'agent',
          approval_policy: parsed[:options].approvalPolicy,
          sandbox_mode: parsed[:options].sandboxMode
        )

        turn = runtime[:turn_service].start_turn(
          threadId: thread[:id],
          request: { prompt: prompt, model: parsed[:options].model, mode: 'agent' }
        )

        streamed = false
        unsubscribe = unless parsed[:json]
                        runtime[:event_bus].subscribe(thread[:id]) do |event|
                          if event[:kind] == 'assistant_text_delta' && event.dig(:item, :kind) == 'assistant_text'
                            streamed = true
                            io[:stdout].write(event.dig(:item, :text))
                          end
                        end
                      end

        status = runtime[:run_turn].call(thread[:id], turn[:turn_id])
        unsubscribe&.call

        items = runtime[:session_store].load_items(thread[:id])

        if parsed[:json]
          io[:stdout].write("#{JSON.generate({ threadId: thread[:id], turnId: turn[:turn_id], status: status,
                                               items: items })}\n")
        else
          unless streamed
            text = assistant_text(items)
            io[:stdout].write(text) if text
          end
          io[:stdout].write("\n")
        end

        status == 'completed' ? ServeExitCode::OK : ServeExitCode::RUNTIME
      rescue StandardError => e
        io[:stderr].write("deepforge run: #{error_message(e)}\n")
        ServeExitCode::RUNTIME
      ensure
        shutdown_runtime(runtime, io, 'deepforge run')
      end
    end

    # 方法功能：启动交互式聊天会话，支持 TTY 终端和管道输入两种模式
    # 参数：argv - 命令行参数；io - IO 流哈希
    # 返回值：整数退出码
    # 使用方法：deepforge chat --model deepseek-chat
    def self.run_chat(argv, io)
      parsed = parse_shared_options(argv, io)
      return write_parse_error(parsed, io, 'deepforge chat') unless parsed[:ok]

      runtime = nil
      begin
        runtime = create_runtime(parsed[:options], io)
        thread = runtime[:thread_service].create(
          title: string_flag(argv, ['title']) || 'CLI chat',
          workspace: parsed[:workspace],
          model: parsed[:options].model,
          mode: 'agent',
          approval_policy: parsed[:options].approvalPolicy,
          sandbox_mode: parsed[:options].sandboxMode
        )

        input = io[:stdin] || $stdin
        terminal = input.tty?

        if terminal
          loop do
            prompt = io[:stdout].gets("\n> ")
            break if prompt.nil?

            prompt = prompt.chomp
            break unless run_chat_turn(runtime: runtime, threadId: thread[:id], prompt: prompt,
                                       model: parsed[:options].model, io: io)
          end
        else
          input.each_line do |line|
            prompt = line.chomp
            break unless run_chat_turn(runtime: runtime, threadId: thread[:id], prompt: prompt,
                                       model: parsed[:options].model, io: io)
          end
        end

        ServeExitCode::OK
      rescue StandardError => e
        io[:stderr].write("deepforge chat: #{error_message(e)}\n")
        ServeExitCode::RUNTIME
      ensure
        shutdown_runtime(runtime, io, 'deepforge chat')
      end
    end

    # 方法功能：执行单次聊天轮次，流式输出助手回复
    # 参数：runtime - 运行时实例；threadId - 线程 ID；prompt - 用户输入；model - 模型名称；io - IO 流
    # 返回值：Boolean，true 表示继续对话，false 表示退出
    def self.run_chat_turn(runtime:, threadId:, prompt:, model:, io:)
      prompt = prompt.strip
      return false if prompt.empty? || prompt == '/exit' || prompt == '/quit'

      turn = runtime[:turn_service].start_turn(
        threadId: threadId,
        request: { prompt: prompt, model: model, mode: 'agent' }
      )

      streamed = false
      unsubscribe = runtime[:event_bus].subscribe(threadId) do |event|
        next unless event[:turn_id] == turn[:turn_id]
        next unless event[:kind] == 'assistant_text_delta' && event.dig(:item, :kind) == 'assistant_text'

        streamed = true
        io[:stdout].write(event.dig(:item, :text))
      end

      runtime[:run_turn].call(threadId, turn[:turn_id])
      unsubscribe.call

      unless streamed
        items = runtime[:session_store].load_items(threadId)
        io[:stdout].write(assistant_text(items))
      end

      io[:stdout].write("\n")
      true
    end

    # 方法功能：直接调用工具执行器，支持列出可用工具和执行指定工具
    # 参数：argv - 命令行参数；io - IO 流哈希
    # 返回值：整数退出码
    # 使用方法：deepforge exec --list-tools 或 deepforge exec tool_name --args '{"key":"value"}'
    def self.run_exec(argv, io)
      parsed = parse_shared_options(argv, io)
      return write_parse_error(parsed, io, 'deepforge exec') unless parsed[:ok]

      runtime = nil
      begin
        runtime = create_runtime(parsed[:options], io)
      rescue StandardError => e
        io[:stderr].write("deepforge exec: #{error_message(e)}\n")
        return ServeExitCode::RUNTIME
      end

      host = runtime[:tool_host] || LocalToolHost.new(tools: build_default_local_tools)
      context = build_exec_context(parsed[:options], parsed[:workspace])
      json = parsed[:json]

      begin
        if has_flag?(argv, 'list-tools')
          tools = host.listTools(context)
          if json
            io[:stdout].write("#{JSON.generate({ tools: tools })}\n")
          else
            io[:stdout].write("#{tools.map { |t| t[:name] }.join("\n")}\n")
          end
          return ServeExitCode::OK
        end

        tool_name = positionals(argv).first
        unless tool_name
          io[:stderr].write("deepforge exec: missing tool name (use --list-tools to inspect tools)\n")
          return ServeExitCode::USAGE
        end

        args_text = string_flag(argv, ['args']) || '{}'
        args = parse_json_object(args_text)
        unless args[:ok]
          io[:stderr].write("deepforge exec: #{args[:message]}\n")
          return ServeExitCode::CONFIG
        end

        result = host.execute({
                                callId: "cli_#{Time.now.to_i.to_s(36)}",
                                toolName: tool_name,
                                arguments: args[:value]
                              }, context)

        if json
          io[:stdout].write("#{JSON.generate(result[:item])}\n")
        elsif result.dig(:item, :kind) == 'tool_result'
          io[:stdout].write("#{format_tool_output(result.dig(:item, :output))}\n")
        else
          io[:stdout].write("#{JSON.pretty_generate(result[:item])}\n")
        end

        result.dig(:item, :kind) == 'tool_result' && result.dig(:item, :isError) ? ServeExitCode::RUNTIME : ServeExitCode::OK
      rescue StandardError => e
        io[:stderr].write("deepforge exec: #{error_message(e)}\n")
        ServeExitCode::RUNTIME
      ensure
        shutdown_runtime(runtime, io, 'deepforge exec')
      end
    end

    # 方法功能：解析所有子命令共享的通用选项
    # 参数：argv - 命令行参数；io - IO 流哈希
    # 返回值：Hash，包含 :ok、:options、:workspace、:json
    def self.parse_shared_options(argv, io)
      parsed = parse_serve_options_safe(argv, io[:env] || {})
      return parsed unless parsed[:ok]

      {
        ok: true,
        options: parsed[:options],
        workspace: string_flag(argv,
                               ['workspace']) || io[:env]&.dig('DEEPFORGE_WORKSPACE') || io[:cwd]&.call || Dir.pwd,
        json: has_flag?(argv, 'json')
      }
    end

    # 方法功能：创建运行时实例，优先使用注入的 createRuntime，否则使用默认工厂方法
    # 参数：options - ServeOptions 配置对象；io - IO 流哈希
    # 返回值：Hash，运行时实例
    def self.create_runtime(options, io)
      if io[:createRuntime]
        io[:createRuntime].call(options)
      else
        DeepForge::Server.create_deepforge_serve_runtime(options)
      end
    end

    # 方法功能：安全关闭运行时实例
    # 参数：runtime - 运行时实例；io - IO 流哈希；label - 命令标签（用于错误日志）
    def self.shutdown_runtime(runtime, io, label)
      return unless runtime&.dig(:shutdown)

      begin
        runtime[:shutdown].call
      rescue StandardError => e
        io[:stderr].write("#{label}: shutdown failed: #{error_message(e)}\n")
      end
    end

    # 方法功能：构建工具执行所需的上下文环境
    # 参数：options - ServeOptions 配置；workspace - 工作区路径
    # 返回值：Hash，包含 threadId、turnId、workspace、model 等上下文信息
    def self.build_exec_context(options, workspace)
      model_profiles = model_context_profiles_from_config(
        context_compaction: options.context_compaction,
        models: options.models
      )
      {
        threadId: 'cli_exec',
        turnId: 'cli_exec',
        workspace: workspace,
        threadMode: 'agent',
        model: model_capabilities_for_model(options.model, model_profiles),
        memoryPolicy: { enabled: false },
        delegationPolicy: { enabled: false },
        approval_policy: options.approval_policy,
        abortSignal: nil,
        awaitApproval: -> { options.approval_policy == 'auto' ? 'allow' : 'deny' }
      }
    end

    # 方法功能：将参数解析错误输出到 stderr
    # 参数：parsed - 解析结果哈希；io - IO 流；label - 命令标签
    # 返回值：整数退出码
    def self.write_parse_error(parsed, io, label)
      io[:stderr].write("#{label}: #{parsed[:message]}\n")
      io[:stderr].write("#{JSON.pretty_generate(parsed[:issues])}\n") if parsed[:issues]
      parsed[:exitCode]
    end

    # 方法功能：从对话轮次的 items 中提取助手回复文本并拼接
    # 参数：items - 对话项数组
    # 返回值：拼接后的助手文本字符串
    def self.assistant_text(items)
      items
        .select { |item| item[:kind] == 'assistant_text' }
        .map { |item| item[:text] }
        .join("\n")
    end

    # 方法功能：将字符串解析为 JSON 对象，验证是否为 Hash 类型
    # 参数：text - JSON 字符串
    # 返回值：Hash，包含 :ok、:value 或 :message
    def self.parse_json_object(text)
      parsed = JSON.parse(text)
      return { ok: false, message: '--args must be a JSON object' } unless parsed.is_a?(Hash)

      { ok: true, value: parsed }
    rescue JSON::ParserError => e
      { ok: false, message: "invalid --args JSON: #{error_message(e)}" }
    end

    # 方法功能：从命令行参数中提取位置参数（非标志参数）
    # 参数：argv - 命令行参数数组
    # 返回值：位置参数字符串数组
    def self.positionals(argv)
      out = []
      index = 0
      while index < argv.length
        token = argv[index]
        if token == '--'
          out.concat(argv[(index + 1)..])
          break
        end
        if token.start_with?('--')
          flag = token[2..].split('=').first || ''
          index += 1 if !token.include?('=') && VALUE_FLAGS.include?(flag)
          index += 1
          next
        end
        if token.start_with?('-') && token.length > 1
          flag = token[1..]
          index += 1 if VALUE_FLAGS.include?(flag)
          index += 1
          next
        end
        out << token
        index += 1
      end
      out
    end

    # 方法功能：从命令行参数或选项哈希中获取字符串标志的值
    # 参数：argv - 参数数组或哈希；names - 标志名称（支持单个或数组）
    # 返回值：字符串值或 nil
    def self.string_flag(argv, names)
      # If argv is a Hash, look up directly
      if argv.is_a?(Hash)
        name_set = Array(names)
        name_set.each do |name|
          return argv[name.to_sym] if argv[name.to_sym]
          return argv[name] if argv[name]
        end
        return nil
      end

      # Otherwise, parse command-line arguments
      name_set = Array(names).to_set
      index = 0
      while index < argv.length
        token = argv[index]
        if token.start_with?('--')
          eq = token.index('=')
          key = eq ? token[2...eq] : token[2..]
          if name_set.include?(key)
            return eq ? token[(eq + 1)..] : argv[index + 1]
          end
        elsif token.start_with?('-') && name_set.include?(token[1..])
          return argv[index + 1]
        end
        index += 1
      end
      nil
    end

    # 方法功能：检查命令行参数中是否存在指定的布尔标志
    # 参数：argv - 参数数组；name - 标志名称
    # 返回值：Boolean
    def self.has_flag?(argv, name)
      argv.any? { |token| ["--#{name}", "--#{name}=true"].include?(token) }
    end

    # 方法功能：格式化工具输出用于终端显示
    # 参数：output - 工具返回的原始输出对象
    # 返回值：格式化后的字符串
    def self.format_tool_output(output)
      output.is_a?(String) ? output : JSON.pretty_generate(output)
    end

    # 方法功能：从异常对象中安全提取错误消息字符串
    # 参数：error - 异常对象或字符串
    # 返回值：错误消息字符串
    def self.error_message(error)
      error.is_a?(Exception) ? error.message : error.to_s
    end

    # 方法功能：根据配置生成模型上下文画像（占位实现）
    # 参数：contextCompaction - 上下文压缩配置；models - 模型列表
    # 返回值：空哈希
    def self.model_context_profiles_from_config(context_compaction: nil, models: nil)
      {}
    end

    # 方法功能：获取指定模型的能力信息（占位实现）
    # 参数：model - 模型名称；profiles - 上下文画像
    # 返回值：包含 :model 的哈希
    def self.model_capabilities_for_model(model, _profiles)
      { model: model }
    end

    # 方法功能：构建默认本地工具列表（占位实现）
    # 返回值：空数组
    def self.build_default_local_tools
      []
    end

    # 本地工具宿主结构体，用于 exec 命令的工具调用
    LocalToolHost = Struct.new(:tools, keyword_init: true) do
      # 列出所有可用工具
      def listTools(_context)
        tools || []
      end

      # 执行指定工具调用
      def execute(_call, _context)
        { item: { kind: 'tool_result', output: 'Tool executed' } }
      end
    end
  end
end
