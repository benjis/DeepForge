# frozen_string_literal: true

require_relative 'shared'

module DeepForge
  module Loop
    class Pipeline
      class GoalManager
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          goal_timer = context[:goal_timer]

          finish_goal_elapsed_timer(thread_id, goal_timer)
          :continue
        end

        private

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
end
