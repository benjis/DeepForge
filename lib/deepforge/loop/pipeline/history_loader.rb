# frozen_string_literal: true

require_relative 'shared'
require_relative '../history_healing'

module DeepForge
  module Loop
    class Pipeline
      class HistoryLoader
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          context[:signal]
          step_index = context[:step_index] || 0

          thread = @opts[:thread_store]&.get(thread_id)
          turn = @opts[:turns]&.get_turn(thread_id, turn_id)
          context[:thread] = thread
          context[:turn] = turn

          record_pipeline_stage(thread_id, turn_id, :input_received, step_index: step_index)

          loaded_items = @opts[:session_store]&.load_items(thread_id) || []
          healed = HistoryHealing.heal(loaded_items)
          @opts[:session_store]&.rewrite_items(thread_id, healed[:items]) if healed[:changed]

          context[:loaded_items] = loaded_items
          context[:healed] = healed

          record_pipeline_stage(thread_id, turn_id, :input_cached,
                                prefix_volatility_stage_details(PrefixVolatility.detect_volatile_prefix_content(@opts[:prefix])))

          if step_index.positive?
            tool_result_count = healed[:items].count do |item|
              item[:turn_id] == turn_id && item[:kind] == 'tool_result'
            end
            @opts[:events]&.record(
              kind: 'tool_result_upload_wait',
              thread_id: thread_id,
              turn_id: turn_id,
              status: 'waiting',
              tool_result_count: tool_result_count
            )
          end

          items = repair_model_history_items(effective_history_after_latest_compaction(healed[:items]))
          context[:items] = items

          :continue
        end

        private

        def repair_model_history_items(items)
          items
        end

        def effective_history_after_latest_compaction(items)
          (items.length - 1).downto(0) do |index|
            item = items[index]
            return items[index..] if item[:kind] == 'compaction' && (item[:replaced_tokens] || 0).positive?
          end
          items
        end
      end
    end
  end
end
