# frozen_string_literal: true

require_relative 'shared'

module DeepForge
  module Loop
    class Pipeline
      class SteeringDrain
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          signal = context[:signal]

          drain_steering(thread_id, turn_id, signal)
          :continue
        end

        private

        def drain_steering(thread_id, turn_id, _signal)
          pending = @opts[:steering]&.drain || []
          pending.each do |text|
            item = {
              id: next_id('item_steered'),
              turn_id: turn_id,
              thread_id: thread_id,
              role: 'user',
              status: 'completed',
              created_at: now_iso,
              finished_at: now_iso,
              kind: 'user_message',
              text: text
            }
            @opts[:turns]&.apply_item(thread_id, item)
          end
        end
      end
    end
  end
end
