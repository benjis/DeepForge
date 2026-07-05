# frozen_string_literal: true

# 文件用途：轮次路由模块，处理 AI 对话轮次的启动、引导和中断
# 使用方法：通过 POST /v1/threads/:id/turns 端点启动新轮次

require 'json'
require_relative '../response'
require_relative 'runtime_error'
require_relative '../read_json_body'
require_relative '../../contracts/turns'

module DeepForge
  module Server
    module Routes
      # 轮次端点处理模块，提供对话轮次的管理和控制功能
      module Turns
        # 在线程中启动新轮次
        # @param turns [DialogueTurnService] 轮次服务实例
        # @param thread_id [String] 线程 ID
        # @param request [Hash] 请求对象，包含 :body
        # @param on_started [Proc, nil] 轮次开始时的回调函数
        # @return [JsonResponse] 已启动的轮次响应
        def self.start_turn(turns, thread_id, request, on_started: nil)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          # Validate required fields
          unless body.value.is_a?(Hash)
            return DeepForge::Server::Routes::ERRORS[:validation].call('invalid start turn body')
          end

          unless body.value[:prompt].is_a?(String) && !body.value[:prompt].empty?
            return DeepForge::Server::Routes::ERRORS[:validation].call('prompt is required')
          end

          if body.value[:model] && !body.value[:model].is_a?(String)
            return DeepForge::Server::Routes::ERRORS[:validation].call('model must be a string')
          end

          begin
            response = turns.start_turn(thread_id: thread_id, request: body.value)
            on_started&.call(response)
            DeepForge::Server.json_response(response, 202)
          rescue StandardError => e
            raise unless e.message.match?(/not found/i)

            DeepForge::Server::Routes::ERRORS[:not_found].call(e.message)
          end
        end

        # 用新文本引导正在运行的轮次
        # @param turns [DialogueTurnService] 轮次服务实例
        # @param thread_id [String] 线程 ID
        # @param turn_id [String] 轮次 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 引导确认
        def self.steer_turn(turns, thread_id, turn_id, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          unless body.value.is_a?(Hash) && body.value['text'].is_a?(String) && !body.value['text'].empty?
            return DeepForge::Server::Routes::ERRORS[:validation].call('text is required')
          end

          turns.steer_turn(thread_id: thread_id, turn_id: turn_id, text: body.value[:text])
          DeepForge::Server.json_response({ ok: true })
        end

        # 中断正在运行的轮次
        # @param turns [DialogueTurnService] 轮次服务实例
        # @param thread_id [String] 线程 ID
        # @param turn_id [String] 轮次 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 中断响应
        def self.interrupt_turn(turns, thread_id, turn_id, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          parsed = body.value || {}
          result = turns.interrupt_turn(thread_id: thread_id, turn_id: turn_id, discard: parsed[:discard])
          DeepForge::Server.json_response({
                                            threadId: thread_id,
                                            turnId: turn_id,
                                            status: result[:status]
                                          })
        end

        # 压缩线程的上下文
        # @param turns [DialogueTurnService] 轮次服务实例
        # @param thread_id [String] 线程 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 压缩响应
        def self.compact_turn(turns, thread_id, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          req = body.value || {}
          if req.is_a?(Hash) && req[:strategy] && !%w[full targeted recent summary].include?(req[:strategy])
            return DeepForge::Server::Routes::ERRORS[:validation].call('strategy must be one of: full, targeted, recent, summary')
          end

          begin
            response = turns.compact(thread_id: thread_id, request: req)
            DeepForge::Server.json_response(response)
          rescue StandardError => e
            raise unless e.message.match?(/not found/i)

            DeepForge::Server::Routes::ERRORS[:not_found].call(e.message)
          end
        end

        # 根据 ID 获取轮次
        # @param turns [DialogueTurnService] 轮次服务实例
        # @param thread_id [String] 线程 ID
        # @param turn_id [String] 轮次 ID
        # @return [JsonResponse] 轮次数据
        def self.get_turn(turns, thread_id, turn_id)
          turn = turns.get_turn(thread_id, turn_id)
          unless turn
            return DeepForge::Server.json_response({ code: 'not_found', message: "turn not found: #{turn_id}" },
                                                   404)
          end

          DeepForge::Server.json_response(turn)
        end
      end
    end
  end
end
