# frozen_string_literal: true

# 文件用途：记忆路由模块，处理用户记忆的 CRUD 操作
# 使用方法：通过 /v1/memory 端点进行记忆的增删改查

require 'json'
require_relative '../response'
require_relative 'runtime_error'

module DeepForge
  module Server
    module Routes
      # 记忆端点处理模块，提供记忆的创建、读取、更新和删除功能
      module Memory
        # 列出记忆，支持可选的过滤条件
        # @param store [MemoryStore, nil] 记忆存储实例
        # @param request [Hash] 请求对象，包含 :url
        # @return [JsonResponse] 记忆列表
        def self.list_memories(store, request)
          return DeepForge::Server::Routes::ERRORS[:unavailable].call('memory store is unavailable') unless store

          url = URI(request[:url])
          query_params = URI.decode_www_form(url.query || '').to_h
          memories = store.list(
            workspace: query_params['workspace'],
            includeDeleted: query_params['include_deleted'] == 'true'
          )
          DeepForge::Server.json_response({ memories: memories })
        end

        # 创建新记忆
        # @param store [MemoryStore, nil] 记忆存储实例
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 创建的记忆
        def self.create_memory(store, request)
          return DeepForge::Server::Routes::ERRORS[:unavailable].call('memory store is unavailable') unless store

          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          unless body.value.is_a?(Hash)
            return DeepForge::Server::Routes::ERRORS[:validation].call('invalid memory create body')
          end

          unless body.value['content'].is_a?(String) && !body.value['content'].empty?
            return DeepForge::Server::Routes::ERRORS[:validation].call('content is required')
          end

          memory = store.create(body.value)
          DeepForge::Server.json_response({ memory: memory }, 201)
        end

        # 更新现有记忆
        # @param store [MemoryStore, nil] 记忆存储实例
        # @param id [String] 记忆 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 更新后的记忆
        def self.update_memory(store, id, request)
          return DeepForge::Server::Routes::ERRORS[:unavailable].call('memory store is unavailable') unless store

          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          unless body.value.is_a?(Hash)
            return DeepForge::Server::Routes::ERRORS[:validation].call('invalid memory update body')
          end

          if body.value['content'] && (!body.value['content'].is_a?(String) || body.value['content'].empty?)
            return DeepForge::Server::Routes::ERRORS[:validation].call('content must be a non-empty string')
          end

          if body.value['scope'] && !%w[user workspace project].include?(body.value['scope'])
            return DeepForge::Server::Routes::ERRORS[:validation].call('scope must be one of: user, workspace, project')
          end

          if body.value['confidence'] && (!body.value['confidence'].is_a?(Numeric) || body.value['confidence'].negative? || body.value['confidence'] > 1)
            return DeepForge::Server::Routes::ERRORS[:validation].call('confidence must be a number between 0 and 1')
          end

          begin
            memory = store.update(id, body.value)
            DeepForge::Server.json_response({ memory: memory })
          rescue StandardError => e
            DeepForge::Server::Routes::ERRORS[:not_found].call(error_message(e))
          end
        end

        # 删除记忆
        # @param store [MemoryStore, nil] 记忆存储实例
        # @param id [String] 记忆 ID
        # @return [JsonResponse] 已删除的记忆
        def self.delete_memory(store, id)
          return DeepForge::Server::Routes::ERRORS[:unavailable].call('memory store is unavailable') unless store

          begin
            memory = store.delete(id)
            DeepForge::Server.json_response({ memory: memory })
          rescue StandardError => e
            DeepForge::Server::Routes::ERRORS[:not_found].call(error_message(e))
          end
        end

        # 获取记忆诊断信息
        # @param store [MemoryStore, nil] 记忆存储实例
        # @return [JsonResponse] 诊断信息
        def self.memory_diagnostics(store)
          unless store
            return DeepForge::Server.json_response({
                                                     enabled: false,
                                                     root_dir: '',
                                                     activeCount: 0,
                                                     tombstoneCount: 0,
                                                     lastInjectedIds: []
                                                   })
          end

          DeepForge::Server.json_response(store.diagnostics)
        end

        # 从异常中提取错误消息
        # @param error [Exception] 错误实例
        # @return [String] 错误消息
        def self.error_message(error)
          error.is_a?(Exception) ? error.message : error.to_s
        end
      end
    end
  end
end
