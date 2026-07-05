# frozen_string_literal: true

# 文件用途：本地工具宿主，管理工具的注册、执行和审批
# 使用方法：通过 LocalToolHost 类管理工具生命周期，支持审批门控和钩子机制

require 'json'
require_relative 'capability_registry'
require_relative 'tool_hooks'
require_relative 'tool_rate_limit'
require_relative 'read_tracker'

module DeepForge
  module Adapters
    module Tool
      # 工具类型常量：工具调用
      TOOL_KIND_TOOL_CALL = 'tool_call'
      # 工具类型常量：命令执行
      TOOL_KIND_COMMAND_EXECUTION = 'command_execution'
      # 工具类型常量：文件变更
      TOOL_KIND_FILE_CHANGE = 'file_change'

      # 审批策略常量：自动
      POLICY_AUTO = 'auto'
      # 审批策略常量：按需
      POLICY_ON_REQUEST = 'on-request'
      # 审批策略常量：建议
      POLICY_SUGGEST = 'suggest'
      # 审批策略常量：永不
      POLICY_NEVER = 'never'
      # 审批策略常量：不受信任
      POLICY_UNTRUSTED = 'untrusted'

      autoload :BuiltinTools, ::File.join(__dir__, 'builtin_tools')

      # 工具定义结构体，表示一个注册的工具
      # 工具是纯函数，观察中止信号并可能受审批策略保护
      LocalTool = Struct.new(
        :name, :description, :input_schema, :tool_kind, :policy,
        :should_advertise, :execute,
        keyword_init: true
      )

      # 选项结构体
      LocalToolHostOptions = Struct.new(
        :tools, :registry, :allow_list, :hooks, :read_tracker,
        keyword_init: true
      )

      # 类功能：本地工具宿主，管理工具的注册、执行和审批
      class LocalToolHost
        # 方法功能：获取宿主标识符
        # 返回值：字符串 'local'
        ID = 'local'

        attr_reader :id

        # @param options [LocalToolHostOptions]
        # 方法功能：初始化本地工具宿主
        # 参数：options - LocalToolHostOptions 结构体实例
        def initialize(options = LocalToolHostOptions.new)
          @registry = options.registry || CapabilityRegistry.from_local_tools(options.tools || [])
          @allow_list = Set.new(options.allow_list || [])
          @hooks = options.hooks || []
          @read_tracker = ReadTracker.new(normalize_read_tracker_options(options.read_tracker))
          @id = ID
        end

        # List available tools for the given context.
        # @param context [ToolHostContext, nil]
        # @return [Array<CapabilityToolSpec>]
        # 方法功能：列出给定上下文中可用的工具
        # 参数：context - ToolHostContext 可选
        # 返回值：CapabilityToolSpec 数组
        def list_tools(context = nil)
          @registry.list_tools(context)
        end

        # Return diagnostics about all providers.
        # @return [Array<ToolProviderPolicy>]
        # 方法功能：返回所有提供者的诊断信息
        # 返回值：ToolProviderPolicy 数组
        def diagnostics
          @registry.diagnostics
        end

        # Execute a tool call with approval gating.
        # @param call [ToolCallLike]
        # @param context [ToolHostContext]
        # @param on_update [Proc, nil] optional callback for partial updates
        # @return [ToolHostResult]
        # 方法功能：执行工具调用，支持审批门控
        # 参数：call - 工具调用对象，context - 上下文，on_update - 更新回调（可选）
        # 返回值：包含工具结果和审批状态的哈希
        def execute(call, context, on_update: nil)
          raise 'tool call aborted before start' if context.abort_signal.aborted?

          tool_record = @registry.resolve_tool(call.tool_name, context, call.provider_id)
          tool = tool_record.tool

          raise "tool #{call.tool_name} is disabled by policy" if tool.policy == POLICY_NEVER

          # Pre-tool hooks
          pre_hook_results = begin
            run_tool_hooks(hooks: @hooks, invocation: {
                             phase: 'PreToolUse',
                             call: call,
                             context: hook_context(context)
                           })
          rescue StandardError => e
            return {
              item: error_tool_result(context, call, tool, hook_error_message(e), 'hook_failed'),
              approved: false
            }
          end

          pre_hook_decision = apply_pre_tool_hook_results(call, pre_hook_results)
          if pre_hook_decision[:denied]
            return {
              item: error_tool_result(context, pre_hook_decision[:call], tool, pre_hook_decision[:denied],
                                      'hook_denied'),
              approved: false
            }
          end

          active_call = pre_hook_decision[:call]

          # Read-before-edit validation
          read_validation = @read_tracker.validate_before_tool(context: context, call: active_call)
          unless read_validation[:ok]
            return {
              item: error_tool_result(context, active_call, tool, read_validation[:message],
                                      'read_before_edit_required'),
              approved: false
            }
          end

          # Runtime policy check
          if blocked_by_runtime_policy?(tool, active_call, context)
            return {
              item: error_tool_result(
                context, active_call, tool,
                "tool #{active_call.tool_name} is disabled by runtime approval policy",
                'approval_policy_blocked'
              ),
              approved: false
            }
          end

          # Approval check
          needs_approval = requires_approval?(tool, active_call, context)
          if needs_approval
            approval_id = "appr_#{active_call.call_id}"
            approval = create_approval_request(
              id: approval_id,
              thread_id: context.thread_id,
              turn_id: context.turn_id,
              tool_name: active_call.tool_name,
              summary: build_approval_summary(active_call)
            )
            decision = context.await_approval.call(approval)
            unless decision == 'allow'
              item = make_approval_item(
                id: "item_#{approval_id}",
                turn_id: context.turn_id,
                thread_id: context.thread_id,
                approval_id: approval_id,
                tool_name: active_call.tool_name,
                summary: approval[:summary]
              )
              return { item: item, approved: false }
            end
          end

          raise 'tool call aborted while waiting for approval' if context.abort_signal.aborted?

          # Execute the tool
          result = tool.execute.call(active_call.arguments, context) do |update|
            next unless on_update

            partial_item = make_tool_result_item(
              id: "item_#{active_call.call_id}",
              turn_id: context.turn_id,
              thread_id: context.thread_id,
              call_id: active_call.call_id,
              tool_name: active_call.tool_name,
              tool_kind: active_call.tool_kind || tool.tool_kind,
              output: update[:output],
              is_error: update[:is_error],
              status: 'running'
            )
            on_update.call(partial_item)
          end

          # Post-tool hooks
          post_hook_results = begin
            run_tool_hooks(hooks: @hooks, invocation: {
                             phase: 'PostToolUse',
                             call: active_call,
                             context: hook_context(context),
                             result: result
                           })
          rescue StandardError => e
            return {
              item: error_tool_result(context, active_call, tool, hook_error_message(e), 'hook_failed'),
              approved: true
            }
          end

          hooked_result = apply_post_tool_hook_results(result, post_hook_results)
          rate_limited = normalize_rate_limited_tool_output(hooked_result[:output])
          output = rate_limited[:rate_limited] ? rate_limited[:output] : hooked_result[:output]
          is_error = hooked_result[:is_error] || rate_limited[:is_error]

          @read_tracker.observe_tool_result(
            context: context,
            call: active_call,
            output: output,
            is_error: is_error
          )

          item = make_tool_result_item(
            id: "item_#{active_call.call_id}",
            turn_id: context.turn_id,
            thread_id: context.thread_id,
            call_id: active_call.call_id,
            tool_name: active_call.tool_name,
            tool_kind: active_call.tool_kind || tool.tool_kind,
            output: output,
            is_error: is_error
          )

          { item: item, approved: !needs_approval }
        end

        # Clear the read tracker for a thread.
        # @param thread_id [String, nil]
        # 方法功能：清除指定线程的读取追踪器
        # 参数：thread_id - 线程 ID（可选）
        def clear_read_tracker(thread_id = nil)
          @read_tracker.clear(thread_id)
        end

        # Tool builder helper for tests and feature scripts.
        # @param tool [Hash] tool definition
        # @return [LocalTool]
        # 方法功能：定义工具（用于测试和功能脚本）
        # 参数：tool - 工具定义哈希
        # 返回值：LocalTool 结构体实例
        def self.define_tool(tool)
          LocalTool.new(
            name: tool[:name],
            description: tool[:description],
            input_schema: tool[:input_schema],
            tool_kind: tool[:tool_kind] || TOOL_KIND_TOOL_CALL,
            policy: tool[:policy] || POLICY_ON_REQUEST,
            should_advertise: tool[:should_advertise],
            execute: tool[:execute]
          )
        end

        private

        # @return [Boolean]
        # 方法功能：检查工具是否被运行时策略阻止
        # 参数：tool - 工具定义，call - 调用信息，context - 上下文
        # 返回值：布尔值
        def blocked_by_runtime_policy?(tool, call, context)
          return false if interactive_gui_gate_tool?(call.tool_name)
          return false if context.approval_policy != POLICY_NEVER

          tool.policy != POLICY_NEVER
        end

        # @return [Boolean]
        # 方法功能：检查工具是否需要审批
        # 参数：tool - 工具定义，call - 调用信息，context - 上下文
        # 返回值：布尔值
        def requires_approval?(tool, call, context)
          return false if interactive_gui_gate_tool?(call.tool_name)
          return false if tool.policy == POLICY_NEVER || context.approval_policy == POLICY_NEVER

          case context.approval_policy
          when POLICY_AUTO
            false
          when POLICY_ON_REQUEST, POLICY_SUGGEST
            tool.policy != POLICY_AUTO
          when POLICY_UNTRUSTED
            if tool.policy == POLICY_AUTO
              !@allow_list.include?(call.tool_name)
            else
              true
            end
          else
            true
          end
        end

        # @return [Boolean]
        # 方法功能：检查是否为交互式 GUI 门控工具
        # 参数：tool_name - 工具名称
        # 返回值：布尔值
        def interactive_gui_gate_tool?(tool_name)
          %w[user_input request_user_input].include?(tool_name)
        end

        # @return [String]
        # 方法功能：构建审批摘要
        # 参数：call - 工具调用对象
        # 返回值：审批摘要字符串
        def build_approval_summary(call)
          args = call.arguments.map { |key, value| "#{key}=#{value.to_json}" }.join(', ')
          "Run #{call.tool_name}(#{args})"
        end

        # @return [Hash]
        # 方法功能：生成错误工具结果
        # 参数：context - 上下文，call - 调用信息，tool - 工具定义，message - 错误消息，code - 错误代码
        # 返回值：工具结果哈希
        def error_tool_result(context, call, tool, message, code)
          make_tool_result_item(
            id: "item_#{call.call_id}",
            turn_id: context.turn_id,
            thread_id: context.thread_id,
            call_id: call.call_id,
            tool_name: call.tool_name,
            tool_kind: call.tool_kind || tool.tool_kind,
            output: { code: code, error: message },
            is_error: true
          )
        end

        # @return [Hash]
        # 方法功能：构建钩子上下文
        # 参数：context - 工具宿主上下文
        # 返回值：钩子上下文哈希
        def self.hook_context(context)
          {
            thread_id: context.thread_id,
            turn_id: context.turn_id,
            workspace: context.workspace,
            approval_policy: context.approval_policy,
            thread_mode: context.thread_mode
          }.compact
        end

        # @return [String]
        # 方法功能：生成钩子错误消息
        # 参数：error - 异常对象
        # 返回值：错误消息字符串
        def self.hook_error_message(error)
          message = error.is_a?(Error) ? error.message : error.to_s
          "tool hook failed: #{message}"
        end
      end

      # Tiny default tool used by smoke tests: echoes its argument so the
      # rest of the loop has a tool to call when the GUI hasn't provided any.
      # 默认回声工具，用于冒烟测试：回显输入参数
      ECHO_TOOL = LocalToolHost.define_tool(
        name: 'echo',
        description: 'Echo the input argument back to the model.',
        tool_kind: TOOL_KIND_TOOL_CALL,
        input_schema: {
          type: 'object',
          properties: { text: { type: 'string' } },
          required: ['text']
        },
        policy: POLICY_AUTO,
        execute: ->(args, _context, &_block) { { output: { echoed: args[:text] || '' } } }
      )

      # Create a user input tool with the given name.
      # @param name [String]
      # @return [LocalTool]
      # 方法功能：创建用户输入工具
      # 参数：name - 工具名称
      # 返回值：LocalTool 结构体实例
      def self.create_user_input_tool(name)
        LocalToolHost.define_tool(
          name: name,
          description: 'Ask the GUI user a structured question and wait for the answer.',
          tool_kind: TOOL_KIND_TOOL_CALL,
          input_schema: {
            type: 'object',
            properties: {
              prompt: { type: 'string' },
              question: { type: 'string' },
              message: { type: 'string' }
            },
            required: []
          },
          policy: POLICY_AUTO,
          execute: lambda do |args, context, &_block|
            unless context.await_user_input
              return {
                output: { error: 'GUI user input is not available in this runtime context' },
                is_error: true
              }
            end

            input_id = "in_#{SecureRandom.hex(4)}"
            item_id = "item_#{input_id}"
            prompt = args[:prompt]&.to_s || args[:question]&.to_s || args[:message]&.to_s || 'Input requested'
            questions = normalize_user_input_questions(args, input_id, prompt)
            resolution = context.await_user_input.call(id: input_id, item_id: item_id, prompt: prompt,
                                                       questions: questions)
            {
              output: resolution,
              is_error: resolution[:status] == 'cancelled'
            }
          end
        )
      end

      # 用户输入工具实例
      USER_INPUT_TOOL = create_user_input_tool('user_input')
      # 请求用户输入工具实例
      REQUEST_USER_INPUT_TOOL = create_user_input_tool('request_user_input')

      # 方法功能：获取默认的本地工具列表
      # 返回值：LocalTool 数组
      def self.default_local_tools
        BuiltinTools.build_builtin_local_tools + [ECHO_TOOL, USER_INPUT_TOOL, REQUEST_USER_INPUT_TOOL]
      end

      # Build the default tool list including the `create_plan` tool.
      # @param plan_options [Hash] options for create_plan tool
      # @return [Array<LocalTool>]
      # 方法功能：构建包含 create_plan 工具的默认工具列表
      # 参数：plan_options - 计划工具选项
      # 返回值：LocalTool 数组
      def self.build_default_local_tools(plan_options = {})
        default_local_tools + [create_create_plan_tool(plan_options)]
      end

      # Normalize user input questions from tool arguments.
      # @param args [Hash]
      # @param fallback_id [String]
      # @param fallback_prompt [String]
      # @return [Array<Hash>]
      # 方法功能：规范化用户输入问题
      # 参数：args - 参数哈希，fallback_id - 备用 ID，fallback_prompt - 备用提示
      # 返回值：规范化后的问题数组
      def self.normalize_user_input_questions(args, fallback_id, fallback_prompt)
        raw_questions = args[:questions]
        if raw_questions.is_a?(Array) && raw_questions.length.positive?
          questions = raw_questions.each_with_index.filter_map do |question, index|
            normalize_user_input_question(question, index, fallback_id)
          end
          return questions if questions.length.positive?
        end

        [{
          header: 'Input',
          id: args[:id]&.to_s || fallback_id,
          question: fallback_prompt,
          options: []
        }]
      end

      # Normalize a single user input question.
      # @param value [Object]
      # @param index [Integer]
      # @param fallback_id [String]
      # @return [Hash, nil]
      # 方法功能：规范化单个用户输入问题
      # 参数：value - 问题值，index - 索引，fallback_id - 备用 ID
      # 返回值：规范化后的问题哈希或 nil
      def self.normalize_user_input_question(value, index, fallback_id)
        return nil unless value.is_a?(Hash)

        question = value[:question]&.to_s&.strip
        return nil if question.nil? || question.empty?

        options = if value[:options].is_a?(Array)
                    value[:options].filter_map do |opt|
                      normalize_user_input_option(opt)
                    end
                  else
                    []
                  end

        {
          header: value[:header]&.to_s&.strip&.then do |h|
            h.empty? ? "Question #{index + 1}" : h
          end || "Question #{index + 1}",
          id: value[:id]&.to_s&.strip&.then do |i|
            i.empty? ? "#{fallback_id}_#{index + 1}" : i
          end || "#{fallback_id}_#{index + 1}",
          question: question,
          options: options
        }
      end

      # Normalize a user input option.
      # @param value [Object]
      # @return [Hash, nil]
      # 方法功能：规范化用户输入选项
      # 参数：value - 选项值
      # 返回值：规范化后的选项哈希或 nil
      def self.normalize_user_input_option(value)
        return nil unless value.is_a?(Hash)

        label = value[:label]&.to_s&.strip
        return nil if label.nil? || label.empty?

        {
          label: label,
          description: value[:description].to_s
        }
      end
    end
  end
end
