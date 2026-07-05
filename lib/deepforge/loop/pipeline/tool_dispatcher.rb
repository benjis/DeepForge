# frozen_string_literal: true

require_relative 'shared'

module DeepForge
  module Loop
    class Pipeline
      class ToolDispatcher
        include Shared

        PARALLEL_READ_ONLY_TOOL_NAMES = %w[read grep find ls].freeze
        MAX_PARALLEL_TOOL_CALLS = 3

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          signal = context[:signal]
          thread = context[:thread]
          completed_tool_calls = context[:completed_tool_calls]
          effective_mode = context[:effective_mode]
          active_plan_context = context[:active_plan_context]
          model_capabilities = context[:model_capabilities]
          skill_resolution = context[:skill_resolution]
          allowed_tool_names = context[:allowed_tool_names]
          approval_policy = context[:approval_policy]
          tool_specs = context[:tool_specs]
          active_goal_instruction = context[:active_goal_instruction]

          if completed_tool_calls.empty?
            return :continue if context[:stop_reason] == :stop && active_goal_instruction

            return :stop
          end

          dispatched = dispatch_tool_calls(
            calls: completed_tool_calls,
            thread_id: thread_id,
            turn_id: turn_id,
            workspace: thread&.dig(:workspace) || '',
            thread_mode: effective_mode,
            active_plan_context: active_plan_context,
            model_capabilities: model_capabilities,
            active_skill_ids: skill_resolution[:active_skill_ids],
            allowed_tool_names: allowed_tool_names,
            tool_provider_kinds: tool_specs.to_h { |tool| [tool[:name], tool[:provider_kind]] },
            approval_policy: approval_policy,
            signal: signal
          )

          context[:dispatched_result] = dispatched
          dispatched == :aborted ? :aborted : :continue
        end

        private

        def dispatch_tool_calls(input)
          context = create_tool_context(input)
          index = 0

          while index < input[:calls].length
            return :aborted if input[:signal].aborted?

            call = input[:calls][index]
            break unless call

            storm = @opts[:tool_storm_breakers]&.dig(input[:turn_id])&.inspect(call)
            if storm&.dig(:suppress)
              persist_suppressed_tool_call(
                thread_id: input[:thread_id],
                turn_id: input[:turn_id],
                call: call,
                reason: storm[:reason]
              )
              index += 1
              next
            end

            unless parallel_safe_tool_call?(call, input[:approval_policy], input[:tool_provider_kinds])
              result = execute_tool_call(
                thread_id: input[:thread_id],
                turn_id: input[:turn_id],
                call: call,
                context: context
              )
              persist_tool_call_result(input[:thread_id], input[:turn_id], call, result)
              index += 1
              next
            end

            batch = [call]
            index += 1
            suppressed_after_batch = nil

            while batch.length < MAX_PARALLEL_TOOL_CALLS && index < input[:calls].length
              next_call = input[:calls][index]
              break unless next_call
              break unless parallel_safe_tool_call?(next_call, input[:approval_policy], input[:tool_provider_kinds])

              next_storm = @opts[:tool_storm_breakers]&.dig(input[:turn_id])&.inspect(next_call)
              if next_storm&.dig(:suppress)
                suppressed_after_batch = { call: next_call, reason: next_storm[:reason] }
                index += 1
                break
              end

              batch << next_call
              index += 1
            end

            results = batch.map do |entry|
              execute_tool_call(
                thread_id: input[:thread_id],
                turn_id: input[:turn_id],
                call: entry,
                context: context
              )
            end

            batch.each_with_index do |entry, batch_index|
              persist_tool_call_result(input[:thread_id], input[:turn_id], entry, results[batch_index])
            end

            next unless suppressed_after_batch

            persist_suppressed_tool_call(
              thread_id: input[:thread_id],
              turn_id: input[:turn_id],
              call: suppressed_after_batch[:call],
              reason: suppressed_after_batch[:reason]
            )
          end

          :continue
        end

        def parallel_safe_tool_call?(call, approval_policy, tool_provider_kinds)
          return false unless PARALLEL_READ_ONLY_TOOL_NAMES.include?(call[:tool_name])
          return false if call[:tool_kind] && call[:tool_kind] != 'tool_call'
          return false if %w[untrusted never].include?(approval_policy)

          tool_provider_kinds[call[:tool_name]] == 'built-in'
        end

        def create_tool_context(input)
          {
            thread_id: input[:thread_id],
            turn_id: input[:turn_id],
            workspace: input[:workspace],
            thread_mode: input[:thread_mode],
            gui_plan: input[:active_plan_context],
            model: input[:model_capabilities],
            active_skill_ids: input[:active_skill_ids],
            memory_policy: { enabled: !@opts[:memory_store].nil? },
            delegation_policy: { enabled: false },
            allowed_tool_names: input[:allowed_tool_names],
            approval_policy: input[:approval_policy],
            abort_signal: input[:signal]
          }.compact
        end

        def execute_tool_call(input)
          @opts[:inflight].run(
            id: "inflight_#{input[:call][:call_id]}",
            kind: 'tool',
            thread_id: input[:thread_id],
            turn_id: input[:turn_id],
            call_id: input[:call][:call_id]
          ) do
            @opts[:tool_host]&.execute(input[:call], input[:context]) do |item|
              existing = @opts[:turns]&.update_item(input[:thread_id], item[:id], {
                output: item[:kind] == 'tool_result' ? item[:output] : nil,
                is_error: item[:kind] == 'tool_result' ? item[:is_error] : nil,
                status: 'running'
              }.compact)
              @opts[:turns]&.apply_item(input[:thread_id], item) unless existing
            end
          end
        end

        def persist_tool_call_result(thread_id, turn_id, call, result)
          status = result[:item][:kind] == 'tool_result' && result[:item][:is_error] ? 'failed' : 'completed'
          @opts[:turns]&.update_item(thread_id, "item_tool_#{turn_id}_#{call[:call_id]}", {
                                       status: status,
                                       finished_at: now_iso
                                     })
          @opts[:turns]&.apply_item(thread_id, result[:item])
        end

        def persist_suppressed_tool_call(input)
          item = make_tool_result_item(
            "item_#{input[:call][:call_id]}_storm",
            input[:turn_id],
            input[:thread_id],
            input[:call][:call_id],
            input[:call][:tool_name],
            input[:call][:tool_kind] || 'tool_call',
            { error: input[:reason] || 'duplicate tool call suppressed by repeat-loop guard' },
            true
          )

          @opts[:turns]&.update_item(input[:thread_id], "item_tool_#{input[:turn_id]}_#{input[:call][:call_id]}", {
                                       status: 'failed',
                                       finished_at: now_iso
                                     })
          @opts[:turns]&.apply_item(input[:thread_id], item)
          @opts[:events]&.record(
            kind: 'tool_storm_suppressed',
            thread_id: input[:thread_id],
            turn_id: input[:turn_id],
            item_id: item[:id],
            tool_name: input[:call][:tool_name],
            call_id: input[:call][:call_id],
            message: input[:reason] || 'duplicate tool call suppressed by repeat-loop guard'
          )
        end
      end
    end
  end
end
