# frozen_string_literal: true

require_relative 'shared'
require_relative '../compaction/compactor'
require_relative '../token_economy'
require_relative '../request_history_hygiene'
require_relative '../model_request_estimator'

module DeepForge
  module Loop
    class Pipeline
      class RequestBuilder
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          signal = context[:signal]
          model = context[:model]
          items = context[:items]
          plan_turn_active = context[:plan_turn_active]
          context_instructions = context[:context_instructions]
          model_route = context[:model_route]
          tool_specs = context[:tool_specs]

          history = compact_if_needed(items, model, signal, thread_id, turn_id)
          return :aborted if signal.aborted?

          context[:history] = history

          record_pipeline_stage(thread_id, turn_id, :input_compressed, history_items: history.length)

          base_request = {
            thread_id: thread_id,
            turn_id: turn_id,
            model: model,
            system_prompt: @opts[:prefix].system_prompt,
            mode_instruction: plan_turn_active ? AgentLoop::PLAN_MODE_INSTRUCTION : nil,
            context_instructions: context_instructions.empty? ? nil : context_instructions,
            prefix: @opts[:prefix].few_shots,
            history: history,
            tools: tool_specs,
            reasoning_effort: model_route[:reasoning_effort],
            abort_signal: signal
          }.compact

          token_economy = TokenEconomy.normalize_config(@opts[:token_economy])
          raw_input_tokens = token_economy[:enabled] ? ModelRequestEstimator.estimate_input_tokens(base_request) : 0
          economy_request = TokenEconomy.apply_to_request(base_request, token_economy)
          request = economy_request.merge(
            history: RequestHistoryHygiene.apply(economy_request[:history] || [], token_economy[:history_hygiene])
          )

          if token_economy[:enabled]
            record_token_economy_savings(
              thread_id: thread_id,
              turn_id: turn_id,
              model: model,
              raw_input_tokens: raw_input_tokens,
              sent_input_tokens: ModelRequestEstimator.estimate_input_tokens(request)
            )
          end

          context[:request] = request

          record_pipeline_stage(thread_id, turn_id, :pre_send, model: request[:model],
                                                               history_items: request[:history]&.length, tool_count: request[:tools]&.length)
          record_pipeline_stage(thread_id, turn_id, :post_send, model: request[:model])

          :continue
        end

        private

        def compact_if_needed(items, model, _signal, thread_id, turn_id)
          pressure = consume_prompt_pressure(thread_id, model)
          threshold_model = pressure&.dig(:model) || model
          plan = @opts[:compactor]&.plan_compaction(items,
                                                    { model: threshold_model,
                                                      prompt_tokens: pressure&.dig(:prompt_tokens) })
          return items unless plan

          result = @opts[:compactor]&.compact(
            thread_id: thread_id,
            turn_id: turn_id,
            history: items,
            prefix: @opts[:prefix],
            reason: plan[:reason],
            mode: plan[:mode],
            keep_recent: plan[:keep_recent]
          )
          return items unless result

          if result[:replaced_tokens].positive?
            @opts[:tool_host]&.clear_read_tracker(thread_id)
            @opts[:session_store]&.append_item(thread_id, result[:summary_item])
            @opts[:events]&.record(
              kind: 'compaction_completed',
              thread_id: thread_id,
              turn_id: turn_id,
              item_id: result[:summary_item][:id],
              summary: result[:summary_item][:summary] || '',
              replaced_tokens: result[:replaced_tokens],
              pinned_constraints: @opts[:prefix].pinned_constraints
            )
          end

          result[:next]
        end

        def consume_prompt_pressure(thread_id, model)
          return nil unless thread_id

          pressure = @opts[:prompt_token_pressure]&.delete(thread_id)
          return nil unless pressure

          {
            model: pressure[:model] || model,
            prompt_tokens: pressure[:prompt_tokens]
          }
        end

        def record_prompt_pressure(thread_id, model, prompt_tokens)
          return unless thread_id && prompt_tokens.positive?

          current = @opts[:prompt_token_pressure]&.dig(thread_id)
          return if current && current[:prompt_tokens] >= prompt_tokens

          @opts[:prompt_token_pressure]&.store(thread_id, { model: model, prompt_tokens: prompt_tokens })
        end

        def record_token_economy_savings(input)
          saved_tokens = [0, (input[:raw_input_tokens] - input[:sent_input_tokens]).floor].max
          return if saved_tokens <= 0

          usage = @opts[:usage]&.record_token_economy_savings(input[:thread_id], {
                                                                token_economy_savings_tokens: saved_tokens
                                                              })
          @opts[:events]&.record(
            kind: 'usage',
            thread_id: input[:thread_id],
            turn_id: input[:turn_id],
            model: input[:model],
            usage: usage
          )
        end
      end
    end
  end
end
