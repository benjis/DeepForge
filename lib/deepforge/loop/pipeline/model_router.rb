# frozen_string_literal: true

require_relative 'shared'
require_relative '../auto_model_router'

module DeepForge
  module Loop
    class Pipeline
      class ModelRouter
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          signal = context[:signal]
          turn = context[:turn]
          thread = context[:thread]
          items = context[:items]

          model_route = resolve_turn_model(
            thread_id: thread_id,
            turn_id: turn_id,
            latest_request: turn&.dig(:prompt) || '',
            items: items,
            signal: signal,
            reasoning_effort: turn&.dig(:reasoning_effort),
            candidates: [turn&.dig(:model), thread&.dig(:model), @opts.dig(:model, :model)]
          )

          context[:model_route] = model_route

          record_pipeline_stage(thread_id, turn_id, :input_routed,
                                model: model_route[:model],
                                reasoning_effort: model_route[:reasoning_effort])

          model = model_route[:model]
          model_capabilities = @opts[:model_capabilities]&.call(model) ||
                               ModelContextProfile.model_capabilities(model)
          context[:model] = model
          context[:model_capabilities] = model_capabilities

          :continue
        end

        private

        def resolve_turn_model(thread_id:, turn_id:, latest_request:, items:, signal:, reasoning_effort:, candidates:)
          requested_effort = AutoModelRouter.normalize_effort(reasoning_effort)
          resolved = resolve_model_mode(*candidates)

          if resolved[:kind] == :fixed
            result = { model: resolved[:model] }
            result[:reasoning_effort] = requested_effort if requested_effort
            return result
          end

          key = "#{thread_id}:#{turn_id}"
          cached = @opts[:auto_model_routes]&.dig(key)
          if cached
            result = { model: cached[:model] }
            result[:reasoning_effort] = requested_effort || cached[:reasoning_effort]
            return result
          end

          route = AutoModelRouter.resolve(
            model_client: @opts[:model],
            thread_id: thread_id,
            turn_id: turn_id,
            latest_request: latest_request,
            recent_context: AutoModelRouter.recent_context(items, turn_id),
            selected_model_mode: 'auto',
            abort_signal: signal
          )

          @opts[:auto_model_routes]&.store(key, route)
          result = { model: route[:model] }
          result[:reasoning_effort] = requested_effort || route[:reasoning_effort]
          result
        end

        def resolve_model_mode(*candidates)
          candidates.each do |candidate|
            trimmed = candidate&.strip || ''
            next if trimmed.empty?

            return { kind: :auto } if trimmed.downcase == 'auto'

            return { kind: :fixed, model: trimmed }
          end
          { kind: :fixed, model: '' }
        end

        def normalize_requested_reasoning_effort(effort)
          normalized = effort&.strip&.downcase
          normalized && normalized != 'auto' ? normalized : nil
        end
      end
    end
  end
end
