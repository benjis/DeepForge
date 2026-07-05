# frozen_string_literal: true

module DeepForge
  module Loop
    class Pipeline
      STAGES = %i[
        setup steering_drain history_load route_model
        build_context manage_tool_catalog build_request
        handle_response dispatch_tools check_budget manage_goal
      ].freeze

      def initialize(stages = {})
        @stages = stages
      end

      def call(context)
        STAGES.each do |stage_name|
          stage = @stages[stage_name]
          next unless stage

          result = stage.call(context)
          return result if %i[aborted failed stop].include?(result)
        end
        :completed
      end
    end
  end
end
