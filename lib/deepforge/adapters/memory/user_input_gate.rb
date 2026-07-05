# frozen_string_literal: true

require_relative '../../ports/user_input_gate'

module DeepForge
  module Adapters
    module Memory
      class UserInputGate < DeepForge::Ports::UserInputGate
        def initialize
          @pending = {}
        end

        def request(input)
          @pending[input[:id]] = input.merge(resolved: false)
          'submitted'
        end

        def get(id)
          @pending[id]
        end

        def resolve(id, resolution)
          return false unless @pending[id] && !@pending[id][:resolved]

          @pending[id][:resolved] = true
          @pending[id][:resolution] = resolution
          true
        end

        def pending(thread_id: nil)
          @pending.values.select do |p|
            !p[:resolved] && (thread_id.nil? || p[:thread_id] == thread_id)
          end
        end

        def add(id, input)
          @pending[id] = input.merge(resolved: false)
        end

        def reset
          @pending.clear
        end
      end
    end
  end
end
