# frozen_string_literal: true

require_relative 'shared'
require_relative '../tool_call_repair'

module DeepForge
  module Loop
    class Pipeline
      class ResponseHandler
        include Shared

        PARALLEL_READ_ONLY_TOOL_NAMES = %w[read grep find ls].freeze
        MAX_PARALLEL_TOOL_CALLS = 3

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
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          signal = context[:signal]
          request = context[:request]
          tool_provider_metadata = context[:tool_provider_metadata]

          text_accumulator = ''
          reasoning_accumulator = ''
          text_item_id = nil
          reasoning_item_id = nil
          completed_tool_calls = []
          stop_reason = :stop

          if @opts[:model].respond_to?(:stream)
            @opts[:model].stream(request) do |chunk|
              return :aborted if signal.aborted?

              case chunk[:kind]
              when 'assistant_text_delta'
                text_item_id ||= next_id('item_text')
                text_accumulator += chunk[:text]
                @opts[:events]&.record(
                  kind: 'assistant_text_delta',
                  thread_id: thread_id,
                  turn_id: turn_id,
                  item_id: text_item_id,
                  item: make_assistant_text_item(text_item_id, turn_id, thread_id, chunk[:text], 'running')
                )
              when 'assistant_reasoning_delta'
                reasoning_item_id ||= next_id('item_reasoning')
                reasoning_accumulator += chunk[:text]
                @opts[:events]&.record(
                  kind: 'assistant_reasoning_delta',
                  thread_id: thread_id,
                  turn_id: turn_id,
                  item_id: reasoning_item_id,
                  item: make_assistant_reasoning_item(reasoning_item_id, turn_id, thread_id, chunk[:text], 'running')
                )
              when 'tool_call_complete'
                provider = tool_provider_metadata[chunk[:tool_name]]
                tool_kind = tool_kinds[chunk[:tool_name]]
                repaired = ToolCallRepair.repair(chunk[:arguments], {
                                                   tool_name: chunk[:tool_name],
                                                   tool_kind: tool_kind,
                                                   max_string_bytes: @opts.dig(:tool_argument_repair, :max_string_bytes)
                                                 })

                completed_tool_calls << {
                  call_id: chunk[:call_id],
                  tool_name: chunk[:tool_name],
                  provider_id: provider&.dig(:provider_id),
                  tool_kind: tool_kind,
                  arguments: repaired[:arguments]
                }

                item_id = "item_tool_#{turn_id}_#{chunk[:call_id]}"
                @opts[:turns]&.apply_item(thread_id,
                                          make_tool_call_item(item_id, turn_id, thread_id, chunk[:call_id], chunk[:tool_name], tool_kind, repaired[:arguments],
                                                              repaired[:notes]))
                @opts[:events]&.record(
                  kind: 'tool_call_ready',
                  thread_id: thread_id,
                  turn_id: turn_id,
                  item_id: item_id,
                  call_id: chunk[:call_id],
                  tool_name: chunk[:tool_name],
                  ready_count: completed_tool_calls.length
                )
              when 'usage'
                record_prompt_pressure(thread_id, request[:model], chunk[:usage][:prompt_tokens])
                usage = @opts[:usage]&.record(thread_id, chunk[:usage])
                @opts[:events]&.record(kind: 'usage', thread_id: thread_id, turn_id: turn_id, model: request[:model],
                                       usage: usage)
              when 'completed'
                stop_reason = chunk[:stop_reason]&.to_sym || :stop
              when 'error'
                @opts[:events]&.record(kind: 'error', thread_id: thread_id, turn_id: turn_id, message: chunk[:message],
                                       code: chunk[:code])
                stop_reason = :error
              end
            end
          end

          context[:text_accumulator] = text_accumulator
          context[:reasoning_accumulator] = reasoning_accumulator
          context[:text_item_id] = text_item_id
          context[:reasoning_item_id] = reasoning_item_id
          context[:completed_tool_calls] = completed_tool_calls
          context[:stop_reason] = stop_reason

          record_pipeline_stage(thread_id, turn_id, :response_received, stop_reason: stop_reason,
                                                                        tool_call_count: completed_tool_calls.length)

          unless reasoning_accumulator.empty?
            item_id = reasoning_item_id || next_id('item_reasoning')
            @opts[:turns]&.apply_item(thread_id,
                                      make_assistant_reasoning_item(item_id, turn_id, thread_id, reasoning_accumulator,
                                                                    'completed'))
          end

          unless text_accumulator.empty?
            item_id = text_item_id || next_id('item_text')
            @opts[:turns]&.apply_item(thread_id,
                                      make_assistant_text_item(item_id, turn_id, thread_id, text_accumulator,
                                                               'completed'))
          end

          return :failed if stop_reason == :error

          :continue
        end

        def record_prompt_pressure(thread_id, model, prompt_tokens)
          return unless thread_id && prompt_tokens.positive?

          current = @opts[:prompt_token_pressure]&.dig(thread_id)
          return if current && current[:prompt_tokens] >= prompt_tokens

          @opts[:prompt_token_pressure]&.store(thread_id, { model: model, prompt_tokens: prompt_tokens })
        end
      end
    end
  end
end
