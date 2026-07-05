# frozen_string_literal: true

# 文件用途：线程路由模块，处理线程的增删改查以及目标和待办事项管理
# 使用方法：通过 /v1/threads 端点进行线程的完整生命周期管理

require 'json'
require_relative '../response'
require_relative 'runtime_error'
require_relative '../read_json_body'
require_relative '../../contracts/threads'

module DeepForge
  module Server
    module Routes
      # 线程端点处理模块，提供线程的 CRUD 操作和相关功能
      module Threads
        # 解析布尔类型的查询参数
        def self.parse_boolean(value)
          return value unless value.is_a?(String)

          normalized = value.strip.downcase
          return true if %w[1 true yes on].include?(normalized)
          return false if %w[0 false no off].include?(normalized)

          value
        end

        # 从查询参数中解析线程列表选项
        # @param query_params [Hash] 查询参数
        # @return [Hash] 解析后的选项
        def self.parse_list_threads_options(query_params)
          options = {}
          options[:limit] = query_params['limit']&.to_i if query_params['limit']
          options[:search] = query_params['search'] if query_params['search']
          if query_params['include_archived']
            options[:includeArchived] =
              parse_boolean(query_params['include_archived'])
          end
          options[:archivedOnly] = parse_boolean(query_params['archived_only']) if query_params['archived_only']

          if query_params['include']
            include_values = query_params['include'].split(',').map(&:strip).map(&:downcase)
            options[:includeSide] = include_values.include?('side')
          end

          options
        end

        # 列出线程，支持可选的过滤条件
        # @param service [AgentThreadService] 线程服务实例
        # @param request [Hash] 请求对象，包含 :url
        # @return [JsonResponse] 线程列表
        def self.list_threads(service, request)
          url = URI(request[:url])
          query_params = URI.decode_www_form(url.query || '').to_h
          options = parse_list_threads_options(query_params)
          threads = service.list(options)
          DeepForge::Server.json_response({ threads: threads })
        end

        # 创建新线程
        # @param service [AgentThreadService] 线程服务实例
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 创建的线程
        def self.create_thread(service, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          # Validate required fields
          unless body.value.is_a?(Hash) &&
                 body.value[:workspace].is_a?(String) && !body.value[:workspace].empty? &&
                 body.value[:model].is_a?(String) && !body.value[:model].empty?
            return DeepForge::Server::Routes::ERRORS[:validation].call('workspace and model are required')
          end

          if body.value[:mode] && !%w[agent plan].include?(body.value[:mode])
            return DeepForge::Server::Routes::ERRORS[:validation].call('mode must be agent or plan')
          end

          if body.value[:cost_budget_usd] && (!body.value[:cost_budget_usd].is_a?(Numeric) || body.value[:cost_budget_usd] <= 0)
            return DeepForge::Server::Routes::ERRORS[:validation].call('cost_budget_usd must be a positive number')
          end

          thread = service.create(body.value)
          DeepForge::Server.json_response(thread, 201)
        end

        # 根据 ID 获取线程
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @param session_store [SessionStore, nil] 可选的会话存储
        # @return [JsonResponse] 线程数据
        def self.get_thread(service, thread_id, session_store = nil)
          thread = service.get(thread_id)
          unless thread
            return DeepForge::Server.json_response({ code: 'not_found', message: "thread not found: #{thread_id}" },
                                                   404)
          end

          latest_seq = 0
          session_items = []

          if session_store
            latest_seq = session_store.highest_seq(thread_id)
            session_items = session_store.load_items(thread_id)
          end

          hydrated_thread = hydrate_thread_items_from_session(thread, session_items)
          DeepForge::Server.json_response(hydrated_thread.merge(latestSeq: latest_seq))
        end

        # 从会话存储中填充线程项目数据
        # @param thread [Hash] 线程记录
        # @param items [Array] 会话项目列表
        # @return [Hash] 填充后的线程记录
        def self.hydrate_thread_items_from_session(thread, items)
          return thread if items.empty? || thread[:turns]&.empty?

          items_by_turn = {}
          items.each do |item|
            turn_id = item[:turn_id]
            items_by_turn[turn_id] ||= []
            items_by_turn[turn_id] << item
          end

          changed = false
          turns = thread[:turns].map do |turn|
            session_turn_items = items_by_turn[turn[:id]]
            next turn unless session_turn_items

            changed = true
            turn.merge(items: session_turn_items)
          end

          changed ? thread.merge(turns: turns) : thread
        end

        # 更新线程
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 更新后的线程
        def self.update_thread(service, thread_id, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          begin
            Contracts::UpdateThreadRequest.validate(body.value) if body.value.is_a?(Hash)
            updated = service.update(thread_id, body.value)
            DeepForge::Server.json_response(updated)
          rescue ArgumentError => e
            DeepForge::Server.json_response({ code: 'validation_error', message: e.message }, 400)
          rescue StandardError => e
            raise unless e.message.match?(/not found/i)

            DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
          end
        end

        # 删除线程
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @return [JsonResponse] 删除确认
        def self.delete_thread(service, thread_id)
          ok = service.delete(thread_id)
          unless ok
            return DeepForge::Server.json_response({ code: 'not_found', message: "thread not found: #{thread_id}" },
                                                   404)
          end

          DeepForge::Server.json_response({ id: thread_id, deleted: true })
        end

        # 分叉线程
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @param request [Hash, nil] 可选的请求对象，包含 :body
        # @return [JsonResponse] 分叉后的线程
        def self.fork_thread(service, thread_id, request = nil)
          options = {}
          if request
            body = DeepForge::Server.read_json_body(request[:body])
            return body.response unless body.ok

            options = body.value || {}
          end

          begin
            fork = service.fork(thread_id, options)
            DeepForge::Server.json_response(fork, 201)
          rescue StandardError => e
            raise unless e.message.match?(/not found/i)

            DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
          end
        end

        # 获取线程目标
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @return [JsonResponse] 线程目标
        def self.get_thread_goal(service, thread_id)
          goal = service.get_goal(thread_id)
          DeepForge::Server.json_response({ goal: goal })
        rescue StandardError => e
          raise unless e.message.match?(/not found/i)

          DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
        end

        # 设置线程目标
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 更新后的目标
        def self.set_thread_goal(service, thread_id, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          begin
            Contracts::SetThreadGoalRequest.validate(body.value) if body.value.is_a?(Hash)
            goal = service.set_goal(thread_id, body.value)
            DeepForge::Server.json_response({ goal: goal })
          rescue ArgumentError => e
            DeepForge::Server.json_response({ code: 'validation_error', message: e.message }, 400)
          rescue StandardError => e
            if e.message.match?(/not found/i)
              DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
            elsif e.message.match?(/no goal exists/i)
              DeepForge::Server.json_response({ code: 'validation_error', message: e.message }, 400)
            else
              raise
            end
          end
        end

        # 清除线程目标
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @return [JsonResponse] 清除确认
        def self.clear_thread_goal(service, thread_id)
          cleared = service.clear_goal(thread_id)
          DeepForge::Server.json_response({ cleared: cleared })
        rescue StandardError => e
          raise unless e.message.match?(/not found/i)

          DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
        end

        # 获取线程待办事项
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @return [JsonResponse] 线程待办事项列表
        def self.get_thread_todos(service, thread_id)
          todos = service.get_todos(thread_id)
          DeepForge::Server.json_response({ todos: todos })
        rescue StandardError => e
          raise unless e.message.match?(/not found/i)

          DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
        end

        # 设置线程待办事项
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 更新后的待办事项列表
        def self.set_thread_todos(service, thread_id, request)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          begin
            Contracts::SetThreadTodosRequest.validate(body.value) if body.value.is_a?(Hash)
            todos = service.set_todos(thread_id, body.value)
            DeepForge::Server.json_response({ todos: todos })
          rescue ArgumentError => e
            DeepForge::Server.json_response({ code: 'validation_error', message: e.message }, 400)
          rescue StandardError => e
            if e.message.match?(/not found/i)
              DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
            elsif e.message.match?(/todo|plan|in_progress|content/i)
              DeepForge::Server.json_response({ code: 'validation_error', message: e.message }, 400)
            else
              raise
            end
          end
        end

        # 清除线程待办事项
        # @param service [AgentThreadService] 线程服务实例
        # @param thread_id [String] 线程 ID
        # @return [JsonResponse] 清除确认
        def self.clear_thread_todos(service, thread_id)
          cleared = service.clear_todos(thread_id)
          DeepForge::Server.json_response({ cleared: cleared })
        rescue StandardError => e
          raise unless e.message.match?(/not found/i)

          DeepForge::Server.json_response({ code: 'not_found', message: e.message }, 404)
        end
      end
    end
  end
end
