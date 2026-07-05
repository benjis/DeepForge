# frozen_string_literal: true

# 文件用途：待办事项工具
# 使用方法：通过 build 方法创建待办事项管理工具（列表和写入）

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供待办事项管理工具，用于线程级别的任务跟踪
      module TodoTools
        # 待办列表工具名称
        TODO_LIST_TOOL_NAME = 'todo_list'
        # 待办写入工具名称
        TODO_WRITE_TOOL_NAME = 'todo_write'
        # 所有待办工具名称数组
        TODO_TOOL_NAMES = [TODO_LIST_TOOL_NAME, TODO_WRITE_TOOL_NAME].freeze

        # 方法功能：构建所有待办事项工具
        # 参数：thread_service - 线程服务实例
        # 返回值：工具定义数组
        def self.build(thread_service)
          [
            create_todo_list_tool(thread_service),
            create_todo_write_tool(thread_service)
          ]
        end

        # 方法功能：创建待办列表工具
        # 参数：thread_service - 线程服务实例
        # 返回值：工具定义哈希
        def self.create_todo_list_tool(thread_service)
          {
            name: TODO_LIST_TOOL_NAME,
            description: 'Return the current thread todo list. Use this to inspect structured progress state.',
            input_schema: {
              type: 'object',
              properties: {},
              additional_properties: false
            },
            policy: 'auto',
            tool_kind: 'tool_call',
            execute: lambda { |_args, context|
              todos = thread_service.get_todos(context[:thread_id])
              { output: todo_response(todos) }
            }
          }
        end

        # 方法功能：创建待办写入工具
        # 参数：thread_service - 线程服务实例
        # 返回值：工具定义哈希
        def self.create_todo_write_tool(thread_service)
          {
            name: TODO_WRITE_TOOL_NAME,
            description: 'Replace the current thread todo list with the supplied full list.',
            input_schema: {
              type: 'object',
              properties: {
                todos: {
                  type: 'array',
                  description: 'Complete replacement todo table for this thread.',
                  max_items: 200,
                  items: {
                    type: 'object',
                    properties: {
                      id: { type: 'string' },
                      content: { type: 'string' },
                      status: {
                        type: 'string',
                        enum: %w[pending in_progress completed]
                      },
                      source: {
                        type: 'object',
                        properties: {
                          kind: { type: 'string', enum: ['plan'] },
                          plan_id: { type: 'string' },
                          relative_path: { type: 'string' },
                          ordinal: { type: 'integer', minimum: 0 },
                          content_hash: { type: 'string' }
                        },
                        required: %w[kind plan_id relative_path ordinal content_hash],
                        additional_properties: false
                      }
                    },
                    required: %w[content status],
                    additional_properties: false
                  }
                }
              },
              required: ['todos'],
              additional_properties: false
            },
            policy: 'auto',
            tool_kind: 'tool_call',
            execute: lambda { |args, context|
              return error_output('todos must be an array') unless args[:todos].is_a?(Array)

              begin
                normalized = normalize_tool_todos(args[:todos])
                todos = thread_service.set_todos(context[:thread_id], { todos: normalized })
                { output: todo_response(todos) }
              rescue StandardError => e
                error_output(e.message)
              end
            }
          }
        end

        # 方法功能：规范化待办事项列表
        # 参数：todos - 待办事项数组
        # 返回值：规范化后的待办事项数组
        def self.normalize_tool_todos(todos)
          active_seen = false
          todos.map do |todo|
            if todo[:status] != 'in_progress'
              todo
            elsif !active_seen
              active_seen = true
              todo
            else
              todo.merge(status: 'pending')
            end
          end
        end

        # 方法功能：生成待办事项响应
        # 参数：todos - 待办事项数组
        # 返回值：包含待办事项的哈希
        def self.todo_response(todos)
          { todos: todos }
        end

        # 方法功能：生成错误输出格式
        # 参数：message - 错误消息
        # 返回值：包含错误信息的哈希
        def self.error_output(message)
          {
            output: { error: message },
            is_error: true
          }
        end
      end
    end
  end
end
