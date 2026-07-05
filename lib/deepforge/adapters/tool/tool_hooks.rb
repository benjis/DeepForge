# frozen_string_literal: true

# 文件用途：工具钩子系统
# 使用方法：通过 ToolHooks 模块运行工具执行前后的钩子函数

require 'json'
require 'open3'
require 'timeout'

module DeepForge
  module Adapters
    module Tool
      # 工具钩子调用阶段常量
      TOOL_HOOK_PHASE_PRE = 'PreToolUse'
      TOOL_HOOK_PHASE_POST = 'PostToolUse'

      # 工具钩子调用结构体
      ToolHookInvocation = Struct.new(:phase, :call, :context, :result, keyword_init: true)

      # 工具钩子结果结构体
      ToolHookResult = Struct.new(:decision, :message, :arguments, :output, :is_error, keyword_init: true)

      # 已解析的工具钩子结构体（支持函数或命令）
      ResolvedToolHook = Struct.new(:phase, :tool_names, :timeout_ms, :run, :command, :cwd, keyword_init: true)

      # 模块功能：工具钩子系统，支持在工具执行前后运行自定义钩子
      module ToolHooks
        # 方法功能：运行所有匹配的工具钩子
        # 参数：hooks - 已解析的钩子数组，invocation - 钩子调用信息
        # 返回值：钩子结果数组
        def self.run_tool_hooks(hooks:, invocation:)
          matching = hooks.select do |hook|
            hook.phase == invocation.phase && hook_matches_tool?(hook, invocation.call.tool_name)
          end

          results = []
          matching.each do |hook|
            result = if hook.run
                       run_function_hook(hook, invocation)
                     else
                       run_command_hook(hook, invocation)
                     end
            results << result if result
          end
          results
        end

        # Apply pre-tool hook results to a call.
        # @param call [ToolCallLike]
        # @param results [Array<ToolHookResult>]
        # @return [Hash] with :call and optionally :denied
        # 方法功能：应用工具执行前钩子结果
        # 参数：call - 调用信息，results - 钩子结果数组
        # 返回值：包含 :call 和可选 :denied 的哈希
        def self.apply_pre_tool_hook_results(call, results)
          next_call = call
          results.each do |result|
            if result.decision == 'deny'
              return { call: next_call, denied: result.message || 'tool call denied by PreToolUse hook' }
            end

            if result.arguments.is_a?(Hash)
              next_call = next_call.dup
              next_call.arguments = result.arguments
            end
          end
          { call: next_call }
        end

        # Apply post-tool hook results to a result.
        # @param result [Hash] with :output and optionally :is_error
        # @param results [Array<ToolHookResult>]
        # @return [Hash] with :output and optionally :is_error
        # 方法功能：应用工具执行后钩子结果
        # 参数：result - 工具结果，results - 钩子结果数组
        # 返回值：修改后的结果哈希
        def self.apply_post_tool_hook_results(result, results)
          next_result = result.dup
          results.each do |hook_result|
            if hook_result.output
              next_result = {
                output: hook_result.output,
                is_error: hook_result.is_error || next_result[:is_error]
              }
            elsif !hook_result.is_error.nil?
              next_result = next_result.dup
              next_result[:is_error] = hook_result.is_error
            end
          end
          next_result
        end

        class << self
          private

          # Check if a hook matches a tool name.
          # @param hook [ResolvedToolHook]
          # @param tool_name [String]
          # @return [Boolean]
          # 方法功能：检查钩子是否匹配工具名称
          # 参数：hook - 钩子定义，tool_name - 工具名称
          # 返回值：布尔值
          def hook_matches_tool?(hook, tool_name)
            return true if hook.tool_names.nil? || hook.tool_names.empty?

            hook.tool_names.include?(tool_name)
          end

          # Run a function-based hook.
          # @param hook [ResolvedToolHook]
          # @param invocation [ToolHookInvocation]
          # @return [ToolHookResult, nil]
          # 方法功能：运行基于函数的钩子
          # 参数：hook - 钩子定义，invocation - 调用信息
          # 返回值：ToolHookResult 结构体或 nil
          def run_function_hook(hook, invocation)
            timeout_ms = hook.timeout_ms || 5000
            with_timeout(timeout_ms, "#{hook.phase} hook timed out") do
              result = hook.run.call(invocation)
              result.is_a?(ToolHookResult) ? result : nil
            end
          end

          # Run a command-based hook.
          # @param hook [ResolvedToolHook]
          # @param invocation [ToolHookInvocation]
          # @return [ToolHookResult, nil]
          # 方法功能：运行基于命令的钩子
          # 参数：hook - 钩子定义，invocation - 调用信息
          # 返回值：ToolHookResult 结构体或 nil
          def run_command_hook(hook, invocation)
            payload = invocation.to_h.to_json
            cwd = hook.cwd || invocation.context&.workspace

            stdout_str = ''
            stderr_str = ''

            exit_code = nil
            Open3.popen3(hook.command, chdir: cwd) do |stdin, stdout, stderr, wait_thr|
              stdin.write(payload)
              stdin.close

              stdout_thread = Thread.new { stdout_str = stdout.read }
              stderr_thread = Thread.new { stderr_str = stderr.read }

              stdout_thread.join
              stderr_thread.join
              exit_code = wait_thr.value.exitstatus
            end

            timeout_ms = hook.timeout_ms || 5000
            with_timeout(timeout_ms, "#{hook.phase} command hook timed out") do
              # Process already completed
            end

            if exit_code != 0
              return ToolHookResult.new(
                decision: hook.phase == TOOL_HOOK_PHASE_PRE ? 'deny' : nil,
                is_error: hook.phase == TOOL_HOOK_PHASE_POST ? true : nil,
                message: stderr_str.strip.empty? ? "#{hook.phase} command hook exited with #{exit_code}" : stderr_str.strip
              )
            end

            text = stdout_str.strip
            return nil if text.empty?

            begin
              parsed = JSON.parse(text)
              ToolHookResult.new(
                decision: parsed['decision'],
                message: parsed['message'],
                arguments: parsed['arguments'],
                output: parsed['output'],
                is_error: parsed['is_error']
              )
            rescue JSON::ParserError
              ToolHookResult.new(message: text)
            end
          end

          # Execute a block with a timeout.
          # @param timeout_ms [Integer]
          # @param message [String]
          # @yield block to execute
          # @return [Object] result of the block
          # 方法功能：在超时限制内执行代码块
          # 参数：timeout_ms - 超时时间（毫秒），message - 超时消息
          # 返回值：代码块返回值
          def with_timeout(timeout_ms, message, &)
            Timeout.timeout(timeout_ms / 1000.0, &)
          rescue Timeout::Error
            raise Timeout::Error, message
          end
        end
      end
    end
  end
end
