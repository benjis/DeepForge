# frozen_string_literal: true

# 文件用途：任务委托工具提供者
# 使用方法：通过 build 方法创建委托工具，用于运行子代理任务

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供 delegate_task 工具，用于运行有界的子代理任务
      module DelegationToolProvider
        # 方法功能：构建委托工具提供者
        # 参数：runtime - 运行时实例
        # 返回值：工具提供者数组
        def self.build(runtime)
          return [] unless runtime

          [{
            id: 'delegation',
            kind: 'delegation',
            enabled: true,
            available: true,
            tools: [
              create_delegate_task_tool(runtime)
            ]
          }]
        end

        # 方法功能：创建 delegate_task 工具
        # 参数：runtime - 运行时实例
        # 返回值：工具定义哈希
        def self.create_delegate_task_tool(runtime)
          {
            name: 'delegate_task',
            description: 'Run a bounded child agent task and return its summary.',
            input_schema: {
              type: 'object',
              properties: {
                label: { type: 'string' },
                prompt: { type: 'string' },
                workspace: { type: 'string' },
                model: { type: 'string' }
              },
              required: ['prompt'],
              additional_properties: false
            },
            policy: 'auto',
            execute: lambda { |args, context|
              prompt = args[:prompt].is_a?(String) ? args[:prompt].strip : ''
              return error_output('prompt is required') if prompt.empty?

              begin
                diagnostics = runtime.diagnostics(context[:thread_id])
                spawn_index = (diagnostics[:child_runs] || []).length + 1

                record = runtime.run_child(
                  parent_thread_id: context[:thread_id],
                  parent_turn_id: context[:turn_id],
                  label: args[:label].is_a?(String) ? args[:label] : nil,
                  prompt: prompt,
                  workspace: args[:workspace].is_a?(String) ? args[:workspace] : context[:workspace],
                  model: args[:model].is_a?(String) ? args[:model] : context.dig(:model, :id),
                  signal: context[:abort_signal]
                )

                result = {
                  child_id: record[:id],
                  status: record[:status],
                  summary: record[:summary],
                  error: record[:error],
                  usage: record[:usage]
                }

                if spawn_index > 1
                  result[:warning] =
                    "This is child agent spawn ##{spawn_index} for the thread. Spawn only when the extra prefix/cache cost is worth it."
                end

                {
                  output: result,
                  is_error: %w[failed aborted].include?(record[:status])
                }
              rescue StandardError => e
                error_output("delegation failed: #{e.message}")
              end
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
