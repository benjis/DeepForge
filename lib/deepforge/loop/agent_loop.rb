# frozen_string_literal: true

# 文件用途：缓存优先的智能体主循环（Agent Loop）—— 轻量级编排器
# 使用方法：通过 `AgentLoop.new(opts).run_turn(thread_id, turn_id)` 驱动对话轮次
# 核心职责：
#   1. 编排管道阶段，管理共享状态
#   2. 控制轮次迭代循环
#   3. 处理异常和清理

require 'json'
require 'securerandom'
require_relative 'pipeline'
require_relative 'pipeline/setup'
require_relative 'pipeline/steering_drain'
require_relative 'pipeline/history_loader'
require_relative 'pipeline/model_router'
require_relative 'pipeline/context_builder'
require_relative 'pipeline/tool_catalog_manager'
require_relative 'pipeline/request_builder'
require_relative 'pipeline/response_handler'
require_relative 'pipeline/tool_dispatcher'
require_relative 'pipeline/budget_gate'
require_relative 'pipeline/goal_manager'
require_relative 'compaction/compactor'
require_relative 'inflight_tracker'
require_relative 'steering_queue'
require_relative 'token_economy'
require_relative 'request_history_hygiene'
require_relative 'model_request_estimator'
require_relative 'auto_model_router'
require_relative 'tool_storm_breaker'
require_relative 'history_healing'
require_relative 'tool_call_repair'
require_relative '../cache/immutable_prefix'
require_relative '../cache/prefix_volatility'
require_relative '../cache/tool_catalog_fingerprint'

module DeepForge
  module Loop
    class AgentLoop
      PARALLEL_READ_ONLY_TOOL_NAMES = %w[read grep find ls].freeze
      MAX_PARALLEL_TOOL_CALLS = 3
      DEFAULT_COMPACTION_SUMMARY_TIMEOUT_MS = 15_000
      DEFAULT_COMPACTION_SUMMARY_MAX_TOKENS = 1_200
      DEFAULT_COMPACTION_SUMMARY_INPUT_MAX_BYTES = 96 * 1024

      PIPELINE_STAGE_LABELS = {
        setup: 'Setup',
        pre_start: 'Pre-Start',
        post_start: 'Post-Start',
        input_received: 'Input Received',
        input_cached: 'Input Cached',
        input_routed: 'Input Routed',
        input_compressed: 'Input Compressed',
        input_remembered: 'Input Remembered',
        pre_send: 'Pre-Send',
        post_send: 'Post-Send',
        response_received: 'Response Received'
      }.freeze

      PLAN_MODE_INSTRUCTION = [
        'You are in Plan mode.',
        'Investigate the task first using read-only tools and commands: prefer `read`, `grep`, `find`, `ls`, and safe read-only `bash` commands to gather the facts you need.',
        'Do NOT modify project files, apply edits, or run mutating commands in this mode.',
        'When you understand the task well enough, call the `create_plan` tool to save a complete implementation plan as Markdown.',
        'Use `operation: "draft"` for the first plan, and `operation: "refine"` when revising an existing plan; you may call `create_plan` multiple times as the plan evolves.',
        'Write concrete, actionable steps (summary, implementation steps, tests, risks) rather than vague intentions.',
        'After saving, give the user a short summary of the plan and what to review.'
      ].join("\n")

      def initialize(opts)
        @opts = opts
        @auto_model_routes = {}
        @prompt_token_pressure = {}
        @tool_storm_breakers = {}
        @tool_catalog_snapshots = {}

        @opts[:auto_model_routes] ||= @auto_model_routes
        @opts[:prompt_token_pressure] ||= @prompt_token_pressure
        @opts[:tool_storm_breakers] ||= @tool_storm_breakers
        @opts[:tool_catalog_snapshots] ||= @tool_catalog_snapshots

        @pipeline = Pipeline.new(
          setup: Pipeline::Setup.new(@opts),
          steering_drain: Pipeline::SteeringDrain.new(@opts),
          history_load: Pipeline::HistoryLoader.new(@opts),
          route_model: Pipeline::ModelRouter.new(@opts),
          build_context: Pipeline::ContextBuilder.new(@opts),
          manage_tool_catalog: Pipeline::ToolCatalogManager.new(@opts),
          build_request: Pipeline::RequestBuilder.new(@opts),
          handle_response: Pipeline::ResponseHandler.new(@opts),
          dispatch_tools: Pipeline::ToolDispatcher.new(@opts),
          check_budget: Pipeline::BudgetGate.new(@opts),
          manage_goal: Pipeline::GoalManager.new(@opts)
        )
      end

      def run_turn(thread_id, turn_id)
        signal = @opts[:turns]&.get_abort_controller(turn_id)

        if @opts.dig(:tool_storm, :enabled) != false
          @tool_storm_breakers[turn_id] = ToolStormBreaker.new(@opts[:tool_storm] || {})
        end

        context = {
          thread_id: thread_id,
          turn_id: turn_id,
          signal: signal,
          opts: @opts,
          step_index: 0
        }

        step = 0
        result = nil
        loop do
          return :aborted if signal&.aborted?

          context[:step_index] = step

          result = @pipeline.call(context)
          return result if %i[aborted failed stop].include?(result)

          step += 1
        rescue StandardError => e
          fail_turn(thread_id, turn_id, e.message)
          return :failed
        end

        @opts[:turns]&.finish_turn(thread_id: thread_id, turn_id: turn_id, status: result.to_s)
        result
      rescue StandardError => e
        fail_turn(thread_id, turn_id, e.message)
        :failed
      ensure
        finish_goal_elapsed_timer(thread_id, context&.dig(:goal_timer))
        @auto_model_routes.delete("#{thread_id}:#{turn_id}")
        @tool_storm_breakers.delete(turn_id)
      end

      def record_pipeline_stage(thread_id, turn_id, stage, details = nil)
        event = {
          kind: 'pipeline_stage',
          thread_id: thread_id,
          turn_id: turn_id,
          stage: stage,
          label: PIPELINE_STAGE_LABELS[stage]
        }
        event[:details] = details if details && !details.empty?
        @opts[:events]&.record(event)
      end

      def self.default_prefix
        ImmutablePrefixBuilder.create(
          system_prompt: 'You are DeepForge, a careful and helpful assistant.',
          pinned_constraints: ['user: preserve recent turns', 'project: keep responses concise']
        )
      end

      private

      def now_ms
        @opts[:now_ms]&.call || (Time.now.to_f * 1000).to_i
      end

      def now_iso
        @opts[:now_iso]&.call || Time.now.utc.strftime('%FT%TZ')
      end

      def fail_turn(thread_id, turn_id, message)
        @opts[:turns]&.finish_turn(thread_id: thread_id, turn_id: turn_id, status: 'failed', error: message)
      end

      def finish_goal_elapsed_timer(thread_id, timer)
        return unless timer

        elapsed_seconds = [0, ((now_ms - timer[:started_at_ms]) / 1000).floor].max
        return if elapsed_seconds <= 0

        current = @opts[:thread_store]&.get(thread_id)
        current_goal = current&.dig(:goal)
        return unless current && current_goal
        return unless current_goal[:created_at] == timer[:created_at] && current_goal[:objective] == timer[:objective]

        now = now_iso
        goal = current_goal.merge(
          time_used_seconds: (current_goal[:time_used_seconds] || 0) + elapsed_seconds,
          updated_at: now
        )
        updated = current.merge(goal: goal, updated_at: now)
        @opts[:thread_store]&.upsert(updated)
        @opts[:events]&.record(kind: 'goal_updated', thread_id: thread_id, goal: goal)
      end
    end
  end
end
