# frozen_string_literal: true

# 文件用途：代码审查服务
# 使用方法：在隔离的环境中运行代码审查。创建独立的智能体循环实例，使用只读工具集
#           执行审查任务。支持中止信号、错误处理和审查结果解析。

require_relative '../loop/inflight_tracker'
require_relative '../loop/steering_queue'
require_relative '../loop/compaction/compactor'
require_relative '../loop/agent_loop'
require_relative '../loop/model_context_profile'
require_relative '../cache/immutable_prefix'
require_relative '../adapters/tool/local_tool_host'
require_relative '../adapters/tool/builtin_tools'
require_relative '../adapters/in_memory/approval_gate'
require_relative '../adapters/in_memory/user_input_gate'
require_relative '../review/review_prompt'
require_relative '../review/review_output'
require_relative '../review/git_review_target'
require_relative 'runtime_event_recorder'
require_relative 'dialogue_turn_service'
require_relative 'agent_thread_service'
require_relative 'usage_service'

module DeepForge
  module Services
    # 代码审查服务：使用智能体循环运行隔离的代码审查。
    class ReviewService
      # 初始化审查服务
      # 参数：deps - 依赖注入哈希（含 turns, thread_store, model, now_iso 等）
      def initialize(deps)
        @deps = deps
      end

      # 运行代码审查任务
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID，review_item_id - 审查项 ID，
      #        target - 审查目标配置，model - 模型名称（可选）
      # 返回值：String，审查结果状态（'completed', 'failed', 'aborted'）
      def run_review(thread_id:, turn_id:, review_item_id:, target:, model: nil)
        signal = @deps[:turns].get_abort_controller(turn_id)

        unless signal
          fail_review(thread_id: thread_id, turn_id: turn_id, review_item_id: review_item_id,
                      message: 'no abort controller for review turn')
          return 'failed'
        end

        if signal.rejected?
          abort_review(thread_id: thread_id, turn_id: turn_id, review_item_id: review_item_id)
          return 'aborted'
        end

        begin
          thread = @deps[:thread_store].get(thread_id)
          raise "thread not found: #{thread_id}" unless thread

          resolved = DeepForge::Review.resolve_review_target_prompt(
            target: DeepForge::Review::ResolveReviewTargetOptions.new(target: target,
                                                                      workspace: thread[:workspace] || '')
          )

          if signal.rejected?
            abort_review(thread_id: thread_id, turn_id: turn_id, review_item_id: review_item_id)
            return 'aborted'
          end

          raw_review_text = run_isolated_reviewer(
            prompt: resolved.prompt,
            workspace: thread[:workspace] || '',
            model: model&.strip || thread[:model] || @deps[:default_model],
            signal: signal
          )

          if signal.rejected?
            abort_review(thread_id: thread_id, turn_id: turn_id, review_item_id: review_item_id)
            return 'aborted'
          end

          output = parse_review_output(raw_review_text)
          review_text = render_review_output(output)

          @deps[:turns].update_item(thread_id, review_item_id, {
                                      status: 'completed',
                                      title: resolved.title,
                                      output: output,
                                      review_text: review_text,
                                      finished_at: @deps[:now_iso].call
                                    })

          @deps[:turns].finish_turn(
            thread_id: thread_id,
            turn_id: turn_id,
            status: 'completed'
          )

          'completed'
        rescue StandardError => e
          if signal.rejected?
            abort_review(thread_id: thread_id, turn_id: turn_id, review_item_id: review_item_id)
            return 'aborted'
          end

          message = e.is_a?(StandardError) ? e.message : e.to_s
          fail_review(thread_id: thread_id, turn_id: turn_id, review_item_id: review_item_id, message: message)
          'failed'
        end
      end

      private

      # 在隔离环境中运行审查智能体
      # 参数：input - 审查输入配置（含 prompt, workspace, model, signal）
      # 返回值：String，审查文本结果
      def run_isolated_reviewer(input)
        now_iso = @deps[:now_iso]
        event_bus = DeepForge::Adapters::InMemory::EventBus.new
        session_store = DeepForge::Adapters::InMemory::SessionStore.new
        thread_store = DeepForge::Adapters::Memory::AgentThreadStore.new
        usage = UsageService.new
        ids = DeepForge::Ports::RandomIdGenerator.new
        inflight = InflightTracker.new
        steering = SteeringQueue.new
        compactor = ContextCompactor.new

        events = RuntimeEventRecorder.new(
          event_bus: event_bus,
          session_store: session_store,
          allocate_seq: ->(thread_id) { event_bus.allocate_seq(thread_id) },
          now_iso: now_iso
        )

        turns = DialogueTurnService.new(
          thread_store: thread_store,
          session_store: session_store,
          events: events,
          inflight: inflight,
          steering: steering,
          compactor: compactor,
          ids: ids,
          now_iso: now_iso
        )

        threads = AgentThreadService.new(
          thread_store: thread_store,
          session_store: session_store,
          events: events,
          ids: ids,
          now_iso: now_iso
        )

        review_prefix = ImmutablePrefixBuilder.create(
          system_prompt: DeepForge::Review::DEEPFORGE_REVIEW_PROMPT,
          pinned_constraints: ['system: review mode is read-only and must output strict JSON']
        )

        read_only_tools = DeepForge::Adapters::Tool::BuiltinTools.build_read_only_builtin_local_tools
        tool_host = DeepForge::Adapters::Tool::LocalToolHost.new(
          DeepForge::Adapters::Tool::LocalToolHostOptions.new(
            tools: read_only_tools,
            read_tracker: true
          )
        )

        model_capabilities_fn = @deps[:model_capabilities] || lambda { |model|
          ModelContextProfile.model_capabilities(model)
        }

        agent_loop_opts = {
          thread_store: thread_store,
          session_store: session_store,
          approval_gate: DeepForge::Adapters::InMemory::ApprovalGate.new,
          user_input_gate: DeepForge::Adapters::InMemory::UserInputGate.new,
          model: @deps[:model],
          tool_host: tool_host,
          usage: usage,
          events: events,
          turns: turns,
          inflight: inflight,
          steering: steering,
          compactor: compactor,
          prefix: review_prefix,
          ids: ids,
          now_iso: now_iso,
          model_capabilities: model_capabilities_fn
        }

        agent_loop_opts[:context_compaction] = @deps[:context_compaction] if @deps[:context_compaction]
        agent_loop_opts[:token_economy] = @deps[:token_economy] if @deps[:token_economy]
        agent_loop_opts[:tool_storm] = @deps[:runtime]&.[](:tool_storm) if @deps[:runtime]&.[](:tool_storm)
        if @deps[:runtime]&.[](:tool_argument_repair)
          agent_loop_opts[:tool_argument_repair] =
            @deps[:runtime]&.[](:tool_argument_repair)
        end

        loop = AgentLoop.new(agent_loop_opts)

        child_thread = threads.create({
                                        title: 'Review',
                                        workspace: input[:workspace] || '~',
                                        model: input[:model],
                                        mode: 'agent',
                                        approval_policy: 'auto'
                                      })

        started = turns.start_turn(
          thread_id: child_thread[:id],
          request: {
            prompt: input[:prompt],
            model: input[:model],
            mode: 'agent'
          }
        )

        signal = input[:signal]
        turns.interrupt_turn(thread_id: child_thread[:id], turn_id: started[:turn_id]) if signal&.aborted?

        begin
          status = loop.run_turn(child_thread[:id], started[:turn_id])

          runtime_error = session_store.load_events_since(child_thread[:id], 0)
                                       .find { |event| event[:kind] == 'error' && event[:turn_id] == started[:turn_id] }
          raise runtime_error[:message] if runtime_error&.dig(:kind) == 'error'

          items = session_store.load_items(child_thread[:id])
          text = self.class.summarize_review_turn(items, started[:turn_id])

          raise "reviewer #{status}" if status != :completed && !text&.strip&.any?
          raise "reviewer #{status}: #{text}" if status != :completed

          text
        ensure
          signal&.remove_listener(:abort) if signal.respond_to?(:remove_listener)
        end
      end

      # 标记审查为失败状态
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID，review_item_id - 审查项 ID，message - 错误信息
      # 返回值：void
      def fail_review(thread_id:, turn_id:, review_item_id:, message:)
        @deps[:turns].update_item(thread_id, review_item_id, {
                                    status: 'failed',
                                    review_text: message,
                                    finished_at: @deps[:now_iso].call
                                  })

        @deps[:turns].finish_turn(
          thread_id: thread_id,
          turn_id: turn_id,
          status: 'failed',
          error: message
        )
      end

      # 标记审查为已中止状态
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID，review_item_id - 审查项 ID
      # 返回值：void
      def abort_review(thread_id:, turn_id:, review_item_id:)
        @deps[:turns].update_item(thread_id, review_item_id, {
                                    status: 'aborted',
                                    review_text: 'Review aborted.',
                                    finished_at: @deps[:now_iso].call
                                  })

        @deps[:turns].finish_turn(
          thread_id: thread_id,
          turn_id: turn_id,
          status: 'aborted'
        )
      end

      # 解析审查输出文本为结构化结果
      # 参数：raw_text - 审查原始文本
      # 返回值：Contracts::ReviewOutput，结构化审查结果
      def parse_review_output(raw_text)
        DeepForge::Review.parse_review_output(raw_text)
      end

      # 将结构化审查结果渲染为可读文本
      # 参数：output - 结构化审查结果
      # 返回值：String，渲染后的审查文本
      def render_review_output(output)
        DeepForge::Review.render_review_output(output)
      end

      # 从轮次的消息项中提取审查文本摘要
      # 参数：items - 消息项列表，turn_id - 轮次 ID
      # 返回值：String，拼接后的审查文本
      def self.summarize_review_turn(items, turn_id)
        items
          .select { |i| i[:turn_id] == turn_id && i[:kind] == 'assistant_text' && i[:text]&.strip&.any? }
          .map { |i| i[:text].strip }
          .join("\n\n")
          .strip
      end
    end
  end
end
