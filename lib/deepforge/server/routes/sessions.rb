# frozen_string_literal: true

# 文件用途：会话路由模块，处理会话恢复和线程创建
# 使用方法：通过 POST /v1/sessions/:id/resume-thread 端点恢复会话

require 'json'
require_relative '../response'
require_relative 'runtime_error'

module DeepForge
  module Server
    module Routes
      # 会话端点处理模块，提供会话恢复功能
      module Sessions
        # 恢复会话并创建新线程
        # @param service [AgentThreadService] 线程服务实例
        # @param session_id [String] 会话 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 恢复的会话响应
        def self.resume_session(service, session_id, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          # Validate request body
          return validation_error('invalid resume session body') unless body.value.is_a?(Hash)

          if body.value['mode'] && !%w[agent plan].include?(body.value['mode'])
            return validation_error('mode must be agent or plan')
          end

          if body.value['workspace'] && (!body.value['workspace'].is_a?(String) || body.value['workspace'].empty?)
            return validation_error('workspace must be a non-empty string')
          end

          if body.value['model'] && (!body.value['model'].is_a?(String) || body.value['model'].empty?)
            return validation_error('model must be a non-empty string')
          end

          begin
            result = service.resume_session(session_id, body.value)
            DeepForge::Server.json_response({
                                              threadId: result[:thread][:id],
                                              sessionId: result[:sessionId],
                                              messageCount: result[:messageCount],
                                              summary: result[:thread][:title]
                                            }, 201)
          rescue StandardError => e
            raise unless e.message.match?(/not found/i)

            DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
          end
        end

        # 创建验证错误响应
        # @param message [String] 错误消息
        # @return [JsonResponse] 验证错误响应
        def self.validation_error(message)
          body = {
            code: 'validation_error',
            message: message
          }
          DeepForge::Server.json_response(body, 400)
        end
      end
    end
  end
end
