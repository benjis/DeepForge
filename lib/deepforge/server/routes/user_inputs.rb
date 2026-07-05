# frozen_string_literal: true

# 文件用途：用户输入路由模块，处理用户交互式输入的解析和响应
# 使用方法：通过 POST /v1/user-inputs/:id 端点提交用户输入响应

require 'json'
require_relative '../response'
require_relative 'runtime_error'

module DeepForge
  module Server
    module Routes
      # 用户输入端点处理模块，提供用户交互式输入的解析功能
      module UserInputs
        # 解析待处理的用户输入
        # @param input [Hash] 输入参数，包含 :inputId、:request、:gate、:events
        # @return [JsonResponse] 解析响应
        def self.resolve_user_input(input)
          body = DeepForge::Server.read_json_body(input[:request][:body])
          return body.response unless body.ok

          unless body.value.is_a?(Hash)
            return DeepForge::Server::Routes::ERRORS[:validation].call('invalid user input body')
          end

          if body.value['answers'] && !body.value['answers'].is_a?(Array)
            return DeepForge::Server::Routes::ERRORS[:validation].call('answers must be an array')
          end

          if body.value['answers'].is_a?(Array)
            body.value['answers'].each_with_index do |answer, i|
              unless answer.is_a?(Hash) && answer['id'].is_a?(String) && !answer['id'].empty? && answer['label'].is_a?(String) && !answer['label'].empty?
                return DeepForge::Server::Routes::ERRORS[:validation].call("answer at index #{i} must have id and label strings")
              end
            end
          end

          if body.value['cancelled'] && !body.value['cancelled'].is_a?(TrueClass) && !body.value['cancelled'].is_a?(FalseClass)
            return DeepForge::Server::Routes::ERRORS[:validation].call('cancelled must be a boolean')
          end

          pending = input[:gate].get(input[:inputId])
          unless pending
            return DeepForge::Server::Routes::ERRORS[:not_found].call("user input not found: #{input[:inputId]}")
          end

          resolution = if body.value['cancelled']
                         { status: 'cancelled' }
                       else
                         { status: 'submitted', answers: body.value['answers'] || [] }
                       end

          ok = input[:gate].resolve(input[:inputId], resolution)
          unless ok
            return DeepForge::Server::Routes::ERRORS[:conflict].call("user input already resolved: #{input[:inputId]}")
          end

          input[:events].record({
                                  kind: 'user_input_resolved',
                                  threadId: pending[:thread_id],
                                  turnId: pending[:turn_id],
                                  itemId: pending[:itemId],
                                  inputId: pending[:id],
                                  status: resolution[:status],
                                  prompt: pending[:prompt]
                                })

          response = {
            inputId: input[:inputId],
            status: resolution[:status]
          }
          response[:answers] = resolution[:answers] if resolution[:status] == 'submitted'

          DeepForge::Server.json_response(response)
        end
      end
    end
  end
end
