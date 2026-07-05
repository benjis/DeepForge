# frozen_string_literal: true

require_relative '../../ports/event_bus'

module DeepForge
  module Adapters
    module Memory
      class EventBus < DeepForge::Ports::EventBus
        def initialize
          @subscribers = {}
          @seq_counters = {}
        end

        def allocate_seq(thread_id)
          @seq_counters[thread_id] = (@seq_counters[thread_id] || 0) + 1
        end

        def publish(*args)
          thread_id, event = if args.length == 2
                               args
                             else
                               [args.first[:thread_id], args.first]
                             end
          @subscribers[thread_id]&.each { |handler| handler.call(event) }
        end

        def subscribe(thread_id, &handler)
          @subscribers[thread_id] ||= []
          @subscribers[thread_id] << handler
          -> { @subscribers[thread_id]&.delete(handler) }
        end

        def snapshot_since(_thread_id, _since_seq)
          []
        end

        def highest_seq(thread_id)
          @seq_counters[thread_id] || 0
        end

        def reset
          @subscribers.clear
          @seq_counters.clear
        end
      end
    end
  end
end
