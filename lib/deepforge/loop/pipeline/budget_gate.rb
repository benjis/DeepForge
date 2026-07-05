# frozen_string_literal: true

require_relative 'shared'

module DeepForge
  module Loop
    class Pipeline
      class BudgetGate
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          thread = context[:thread]

          result = check_budget_gate(thread, thread_id, turn_id)
          return :stop if result == :blocked

          :continue
        end

        private

        def check_budget_gate(thread, thread_id, turn_id)
          return :allow unless thread

          budget = thread[:cost_budget_usd]
          return :allow unless budget.is_a?(Numeric) && budget.finite? && budget.positive?

          spent = @opts[:usage]&.for_thread(thread_id)&.dig(:cost_usd) || 0
          if spent >= budget
            message = "Cost budget exhausted for this thread: $#{spent.round(4)} used of $#{budget.round(4)}."
            @opts[:turns]&.apply_item(thread_id,
                                      make_error_item("item_#{turn_id}_budget_limited", thread_id, turn_id, message,
                                                      'budget_limited'))
            @opts[:events]&.record(kind: 'error', thread_id: thread_id, turn_id: turn_id, message: message,
                                   code: 'budget_limited')
            return :blocked
          end

          if spent >= budget * 0.8 && thread[:cost_budget_warning_sent] != true
            message = "Cost budget warning: $#{spent.round(4)} used of $#{budget.round(4)}."
            @opts[:thread_store]&.upsert(thread.merge(cost_budget_warning_sent: true, updated_at: now_iso))
            @opts[:turns]&.apply_item(thread_id,
                                      make_error_item("item_#{turn_id}_budget_warning", thread_id, turn_id, message,
                                                      'budget_warning'))
            @opts[:events]&.record(kind: 'error', thread_id: thread_id, turn_id: turn_id, message: message,
                                   code: 'budget_warning')
          end

          :allow
        end
      end
    end
  end
end
