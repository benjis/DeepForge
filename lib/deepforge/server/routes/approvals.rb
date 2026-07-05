# frozen_string_literal: true

# 文件用途：审批路由模块，处理待审批请求的决策（允许或拒绝）
# 使用方法：通过 POST /v1/approvals/{approvalId} 端点提交审批决策

require 'json'
require_relative '../response'
require_relative 'runtime_error'

module DeepForge
  module Server
    module Routes
      # 审批路由模块，解析待审批请求并生成运行时事件供渲染器消费
      module Approvals
        # 对待审批请求做出决策
        # @param input [Hash] 输入参数，包含 :approvalId、:request、:gate、:events
        # @return [JsonResponse] 决策响应
        def self.decide_approval(input)
          body = DeepForge::Server.read_json_body(input[:request][:body])
          return body.response unless body.ok

          unless body.value.is_a?(Hash) && body.value['decision'].is_a?(String) && !body.value['decision'].empty?
            return DeepForge::Server::Routes::ERRORS[:validation].call('decision is required')
          end

          unless %w[allow deny].include?(body.value['decision'])
            return DeepForge::Server::Routes::ERRORS[:validation].call('decision must be one of: allow, deny')
          end

          if body.value['reason'] && !body.value['reason'].is_a?(String)
            return DeepForge::Server::Routes::ERRORS[:validation].call('reason must be a string')
          end

          approval = input[:gate].get(input[:approvalId])
          unless approval
            return DeepForge::Server::Routes::ERRORS[:not_found].call("approval not found: #{input[:approvalId]}")
          end

          ok = input[:gate].decide(input[:approvalId], body.value['decision'], body.value['reason'])
          unless ok
            return DeepForge::Server::Routes::ERRORS[:conflict].call("approval already decided: #{input[:approvalId]}")
          end

          response = {
            approvalId: input[:approvalId],
            decision: body.value['decision'],
            status: body.value['decision'] == 'allow' ? 'allowed' : 'denied'
          }

          input[:events].record({
                                  kind: 'approval_resolved',
                                  threadId: approval[:thread_id],
                                  turnId: approval[:turn_id],
                                  itemId: nil,
                                  approvalId: input[:approvalId],
                                  toolName: approval[:toolName],
                                  status: response[:status],
                                  summary: approval[:summary]
                                })

          DeepForge::Server.json_response(response)
        end
      end
    end
  end
end
