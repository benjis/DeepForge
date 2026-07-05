# frozen_string_literal: true

require_relative 'shared'

module DeepForge
  module Loop
    class Pipeline
      class Setup
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          return :continue if context[:initialized]

          signal = context[:signal]
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]

          unless signal
            fail_turn(thread_id, turn_id, 'no abort controller for turn')
            return :failed
          end

          goal_timer = start_goal_elapsed_timer(thread_id)
          context[:goal_timer] = goal_timer
          context[:initialized] = true
          record_pipeline_stage(thread_id, turn_id, :setup)
          :continue
        end

        private

        def start_goal_elapsed_timer(thread_id)
          thread = @opts[:thread_store]&.get(thread_id)
          goal = thread&.dig(:goal)
          return nil unless goal && goal[:status] == 'active'

          {
            started_at_ms: now_ms,
            created_at: goal[:created_at],
            objective: goal[:objective]
          }
        end
      end
    end
  end
end
