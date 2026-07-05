# frozen_string_literal: true

# 文件用途：子代理执行器模块
# 使用方法：创建隔离的子代理执行环境，运行委托的子代理任务，
#           支持独立的线程、会话和事件记录。

require 'json'
require_relative '../loop/inflight_tracker'
require_relative '../loop/steering_queue'
require_relative '../loop/compaction/compactor'
require_relative '../loop/agent_loop'
require_relative '../loop/model_context_profile'
require_relative '../cache/immutable_prefix'
require 'deepforge/adapters/in_memory/event_bus'
require 'deepforge/adapters/in_memory/session_store'
require 'deepforge/adapters/memory/agent_thread_store'
require 'deepforge/adapters/in_memory/approval_gate'
require 'deepforge/adapters/in_memory/user_input_gate'
require_relative '../ports/id_generator'
require 'deepforge/services/runtime_event_recorder'
require 'deepforge/services/dialogue_turn_service'
require 'deepforge/services/agent_thread_service'
require 'deepforge/services/usage_service'

module DeepForge
  module Delegation
    # 创建子代理执行器的选项结构体
    ChildAgentExecutorOptions = Struct.new(
      :model, :tool_host, :prefix, :default_model,
      :models, :context_compaction, :approval_policy, :sandbox_mode,
      :token_economy, :runtime, :now_iso, :model_capabilities,
      :skill_runtime, :memory_store,
      keyword_init: true
    )

    # 方法功能：创建子代理执行器
    # 参数：options - ChildAgentExecutorOptions 结构体
    # 返回值：Proc - 接受子运行输入的执行器函数
    def self.create_child_agent_executor(options)
      lambda do |input|
        now_iso = options.now_iso || -> { Time.now.strftime('%FT%TZ') }
        event_bus = DeepForge::Adapters::InMemory::EventBus.new
        session_store = DeepForge::Adapters::InMemory::SessionStore.new
        thread_store = DeepForge::Adapters::Memory::AgentThreadStore.new
        usage = DeepForge::Services::UsageService.new
        ids = DeepForge::Ports::RandomIdGenerator.new
        inflight = InflightTracker.new
        steering = SteeringQueue.new
        compactor = ContextCompactor.new

        events = DeepForge::Services::RuntimeEventRecorder.new(
          event_bus: event_bus,
          session_store: session_store,
          allocate_seq: ->(thread_id) { event_bus.allocate_seq(thread_id) },
          now_iso: now_iso
        )

        turns = DeepForge::Services::DialogueTurnService.new(
          thread_store: thread_store,
          session_store: session_store,
          events: events,
          inflight: inflight,
          steering: steering,
          compactor: compactor,
          ids: ids,
          now_iso: now_iso
        )

        threads = DeepForge::Services::AgentThreadService.new(
          thread_store: thread_store,
          session_store: session_store,
          events: events,
          ids: ids,
          now_iso: now_iso
        )

        model_capabilities_fn = options.model_capabilities || lambda { |model|
          ModelContextProfile.model_capabilities(model)
        }

        agent_loop_opts = {
          thread_store: thread_store,
          session_store: session_store,
          approval_gate: DeepForge::Adapters::InMemory::ApprovalGate.new,
          user_input_gate: DeepForge::Adapters::InMemory::UserInputGate.new,
          model: options.model,
          tool_host: options.tool_host,
          usage: usage,
          events: events,
          turns: turns,
          inflight: inflight,
          steering: steering,
          compactor: compactor,
          prefix: options.prefix,
          ids: ids,
          now_iso: now_iso,
          model_capabilities: model_capabilities_fn
        }

        agent_loop_opts[:context_compaction] = options.context_compaction if options.context_compaction
        agent_loop_opts[:token_economy] = options.token_economy if options.token_economy
        agent_loop_opts[:tool_storm] = options.runtime&.[](:tool_storm) if options.runtime&.[](:tool_storm)
        if options.runtime&.[](:tool_argument_repair)
          agent_loop_opts[:tool_argument_repair] =
            options.runtime&.[](:tool_argument_repair)
        end
        agent_loop_opts[:skill_runtime] = options.skill_runtime if options.skill_runtime
        agent_loop_opts[:memory_store] = options.memory_store if options.memory_store

        loop = AgentLoop.new(agent_loop_opts)

        model = (input[:model] || '').to_s.strip
        model = options.default_model if model.empty?
        child_id = input[:child_id] || ids.next('child')

        thread_request = {
          title: child_thread_title(child_id, label: input[:label]),
          workspace: (input[:workspace] || '~').to_s.strip,
          model: model,
          mode: 'agent',
          approval_policy: options.approval_policy || 'auto'
        }
        thread_request[:sandbox_mode] = options.sandbox_mode if options.sandbox_mode

        child_thread = threads.create(
          thread_request,
          {
            id: child_id,
            title: child_thread_title(child_id, label: input[:label])
          }
        )

        started = turns.start_turn(
          thread_id: child_thread[:id],
          request: {
            prompt: input[:prompt],
            model: model,
            mode: 'agent'
          }
        )

        status = loop.run_turn(child_thread[:id], started[:turn_id])

        runtime_error = session_store.load_events_since(child_thread[:id], 0)
                                     .find { |event| event[:kind] == 'error' && event[:turn_id] == started[:turn_id] }
        raise runtime_error[:message] if runtime_error&.dig(:kind) == 'error'

        items = session_store.load_items(child_thread[:id])
        summary = summarize_child_turn(items, started[:turn_id], status.to_s)

        raise "child agent #{status}: #{summary}" if status.to_s != 'completed'

        {
          summary: summary,
          usage: usage.for_thread(child_thread[:id])
        }
      end
    end

    # 方法功能：生成子线程标题
    # 参数：child_id - 子代理 ID
    #       label - 可选的标签
    # 返回值：String - 格式为 "Child agent: <label>" 的标题
    def self.child_thread_title(child_id, label: nil)
      suffix = label&.strip || child_id
      "Child agent: #{suffix}"
    end

    # 方法功能：总结子代理的回合结果
    # 参数：items - 回合项目列表
    #       turn_id - 回合 ID
    #       status - 状态（'completed'、'failed' 或 'aborted'）
    # 返回值：String - 回合结果摘要
    def self.summarize_child_turn(items, turn_id, status)
      turn_items = items.select { |item| item[:turn_id] == turn_id }

      # Try to get assistant text first
      assistant_text = turn_items
                       .select { |item| item[:kind] == 'assistant_text' }
                       .map { |item| item[:text]&.strip }
                       .compact
                       .reject(&:empty?)
                       .join("\n\n")
                       .strip

      return assistant_text unless assistant_text.empty?

      # Try to get error messages
      errors = turn_items
               .select { |item| item[:kind] == 'error' }
               .map { |item| item[:message]&.strip }
               .compact
               .reject(&:empty?)
               .join("\n")
               .strip

      return errors unless errors.empty?

      # Try to get last tool result
      tool_result = turn_items.reverse.find { |item| item[:kind] == 'tool_result' }
      return stringify_summary(tool_result[:output]) if tool_result

      status == 'completed' ? 'Child agent completed without a text response.' : "Child agent #{status}."
    end

    # 方法功能：将值转换为字符串摘要
    # 参数：value - 待转换的值
    # 返回值：String - 字符串表示
    def self.stringify_summary(value)
      return value.strip if value.is_a?(String)
      return '' if value.nil?

      JSON.generate(value)
    rescue StandardError
      value.to_s
    end
  end
end
