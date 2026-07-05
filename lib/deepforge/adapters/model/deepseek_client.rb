# frozen_string_literal: true

require_relative '../../ports/model_client'

module DeepForge
  module Adapters
    module Model
      class DeepseekClient < DeepForge::Ports::ModelClient
        def initialize(base_url:, api_key:, model:)
          @base_url = base_url
          @api_key = api_key
          @model_name = model
          super(provider: 'deepseek', model: model)
        end

        def stream(request)
          raise NotImplementedError, 'DeepseekClient#stream not yet implemented'
        end

        def complete(_messages, _options = {})
          { content: 'Model response', usage: { promptTokens: 0, completionTokens: 0 } }
        end
      end
    end
  end
end
