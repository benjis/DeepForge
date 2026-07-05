# frozen_string_literal: true

require_relative '../../ports/approval_gate'

module DeepForge
  module Adapters
    module Memory
      class ApprovalGate < DeepForge::Ports::ApprovalGate
        def initialize
          @pending = {}
        end

        def request(approval)
          @pending[approval[:id]] = approval.merge(decided: false)
          'pending'
        end

        def get(id)
          @pending[id]
        end

        def decide(id, decision, reason = nil)
          return false unless @pending[id] && !@pending[id][:decided]

          @pending[id][:decided] = true
          @pending[id][:decision] = decision
          @pending[id][:reason] = reason
          true
        end

        def pending(thread_id: nil)
          @pending.values.select do |p|
            !p[:decided] && (thread_id.nil? || p[:thread_id] == thread_id)
          end
        end

        def add(id, approval)
          @pending[id] = approval.merge(decided: false)
        end
      end
    end
  end
end
