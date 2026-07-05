# frozen_string_literal: true

# 文件用途：记忆工具提供者
# 使用方法：通过 build 方法创建记忆管理工具（创建、更新、删除长期记忆）

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供记忆管理工具，用于创建、更新和删除长期记忆
      module MemoryToolProvider
        # 方法功能：构建记忆工具提供者
        # 参数：store - 记忆存储实例
        # 返回值：工具提供者数组
        def self.build(store)
          return [] unless store

          [{
            id: 'memory',
            kind: 'memory',
            enabled: true,
            available: true,
            tools: [
              create_memory_create_tool(store),
              create_memory_update_tool(store),
              create_memory_delete_tool(store)
            ]
          }]
        end

        # 方法功能：创建记忆创建工具
        # 参数：store - 记忆存储实例
        # 返回值：工具定义哈希
        def self.create_memory_create_tool(store)
          {
            name: 'memory_create',
            description: 'Create a long-term memory after explicit user approval.',
            input_schema: {
              type: 'object',
              properties: {
                content: { type: 'string' },
                scope: { type: 'string', enum: %w[user workspace project] },
                workspace: { type: 'string' },
                tags: { type: 'array', items: { type: 'string' } }
              },
              required: ['content'],
              additional_properties: false
            },
            policy: 'on-request',
            execute: lambda { |args, context|
              content = args[:content].is_a?(String) ? args[:content].strip : ''
              return error_output('content is required') if content.empty?

              scope = %w[user project].include?(args[:scope]) ? args[:scope] : 'workspace'
              workspace = args[:workspace].is_a?(String) ? args[:workspace] : context[:workspace]
              tags = args[:tags].is_a?(Array) ? args[:tags].grep(String) : []

              memory = store.create({
                                      content: content,
                                      scope: scope,
                                      workspace: workspace,
                                      source_thread_id: context[:thread_id],
                                      source_turn_id: context[:turn_id],
                                      tags: tags
                                    })

              { output: { memory: memory } }
            }
          }
        end

        # 方法功能：创建记忆更新工具
        # 参数：store - 记忆存储实例
        # 返回值：工具定义哈希
        def self.create_memory_update_tool(store)
          {
            name: 'memory_update',
            description: 'Update or disable an existing long-term memory.',
            input_schema: {
              type: 'object',
              properties: {
                id: { type: 'string' },
                content: { type: 'string' },
                disabled: { type: 'boolean' }
              },
              required: ['id'],
              additional_properties: false
            },
            policy: 'on-request',
            execute: lambda { |args, _context|
              return error_output('id is required') unless args[:id].is_a?(String)

              updates = {}
              updates[:content] = args[:content] if args[:content].is_a?(String)
              updates[:disabled] = args[:disabled] if args[:disabled].is_a?(Boolean)

              memory = store.update(args[:id], updates)
              { output: { memory: memory } }
            }
          }
        end

        # 方法功能：创建记忆删除工具
        # 参数：store - 记忆存储实例
        # 返回值：工具定义哈希
        def self.create_memory_delete_tool(store)
          {
            name: 'memory_delete',
            description: 'Delete a long-term memory by writing a tombstone.',
            input_schema: {
              type: 'object',
              properties: { id: { type: 'string' } },
              required: ['id'],
              additional_properties: false
            },
            policy: 'on-request',
            execute: lambda { |args, _context|
              return error_output('id is required') unless args[:id].is_a?(String)

              memory = store.delete(args[:id])
              { output: { memory: memory } }
            }
          }
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
