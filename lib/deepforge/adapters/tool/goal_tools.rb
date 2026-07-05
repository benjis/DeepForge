# frozen_string_literal: true

# 文件用途：目标管理工具
# 使用方法：通过 build 方法创建目标相关的工具（获取、创建、更新目标）

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供目标管理工具，用于线程级别的目标创建、查询和更新
      module GoalTools
        # 获取目标工具名称
        GET_GOAL_TOOL_NAME = 'get_goal'
        # 创建目标工具名称
        CREATE_GOAL_TOOL_NAME = 'create_goal'
        # 更新目标工具名称
        UPDATE_GOAL_TOOL_NAME = 'update_goal'
        # 所有目标工具名称数组
        GOAL_TOOL_NAMES = [GET_GOAL_TOOL_NAME, CREATE_GOAL_TOOL_NAME, UPDATE_GOAL_TOOL_NAME].freeze

        # 方法功能：构建所有目标管理工具
        # 参数：thread_service - 线程服务实例
        # 返回值：工具定义数组
        def self.build(thread_service)
          [
            create_get_goal_tool(thread_service),
            create_create_goal_tool(thread_service),
            create_update_goal_tool(thread_service)
          ]
        end

        # 方法功能：创建获取目标工具
        # 参数：thread_service - 线程服务实例
        # 返回值：工具定义哈希
        def self.create_get_goal_tool(thread_service)
          {
            name: GET_GOAL_TOOL_NAME,
            description: 'Get the current goal for this thread, including status, budgets, usage, and remaining token budget.',
            input_schema: {
              type: 'object',
              properties: {},
              additional_properties: false
            },
            policy: 'auto',
            tool_kind: 'tool_call',
            execute: lambda { |_args, context|
              goal = thread_service.get_goal(context[:thread_id])
              { output: goal_response(goal) }
            }
          }
        end

        # 方法功能：创建目标创建工具
        # 参数：thread_service - 线程服务实例
        # 返回值：工具定义哈希
        def self.create_create_goal_tool(thread_service)
          {
            name: CREATE_GOAL_TOOL_NAME,
            description: 'Create a goal only when explicitly requested by the user or system/developer instructions.',
            input_schema: {
              type: 'object',
              properties: {
                objective: {
                  type: 'string',
                  description: 'Required. The concrete objective to start pursuing.'
                },
                token_budget: {
                  type: 'integer',
                  description: 'Optional positive token budget for the new active goal.'
                }
              },
              required: ['objective'],
              additional_properties: false
            },
            policy: 'auto',
            tool_kind: 'tool_call',
            execute: lambda { |args, context|
              objective = args[:objective].to_s.strip
              token_budget = normalize_token_budget(args[:token_budget])

              return error_output('objective is required') if objective.empty?
              return error_output('token_budget must be a positive integer') if token_budget == false

              existing = thread_service.get_goal(context[:thread_id])
              return error_output('cannot create a new goal because this thread already has a goal') if existing

              goal = thread_service.set_goal(context[:thread_id], {
                                               objective: objective,
                                               status: 'active',
                                               **(token_budget ? { token_budget: token_budget } : {})
                                             })

              { output: goal_response(goal) }
            }
          }
        end

        # 方法功能：创建目标更新工具
        # 参数：thread_service - 线程服务实例
        # 返回值：工具定义哈希
        def self.create_update_goal_tool(thread_service)
          {
            name: UPDATE_GOAL_TOOL_NAME,
            description: 'Update the existing goal. Use this tool only to mark the goal achieved or blocked.',
            input_schema: {
              type: 'object',
              properties: {
                status: {
                  type: 'string',
                  enum: %w[complete blocked],
                  description: 'Required. Set to complete only when achieved; set to blocked only when externally blocked.'
                }
              },
              required: ['status'],
              additional_properties: false
            },
            policy: 'auto',
            tool_kind: 'tool_call',
            execute: lambda { |args, context|
              status = args[:status]
              unless %w[complete blocked].include?(status)
                return error_output('update_goal can only mark the existing goal complete or blocked')
              end

              existing = thread_service.get_goal(context[:thread_id])
              return error_output('cannot update goal because this thread does not have a goal') unless existing

              goal = thread_service.set_goal(context[:thread_id], { status: status })
              {
                output: goal_response(
                  goal,
                  status == 'complete' ? 'Goal achieved. Report final usage from this tool result if relevant.' : nil
                )
              }
            }
          }
        end

        # 方法功能：规范化令牌预算值
        # 参数：value - 输入值
        # 返回值：正整数、nil 或 false
        def self.normalize_token_budget(value)
          return nil if value.nil?

          return false unless value.is_a?(Integer) && value.positive?

          value
        end

        # 方法功能：生成目标响应
        # 参数：goal - 目标信息，completion_budget_report - 完成预算报告（可选）
        # 返回值：包含目标和剩余令牌的哈希
        def self.goal_response(goal, completion_budget_report = nil)
          remaining_tokens = ([0, goal[:token_budget] - (goal[:tokens_used] || 0)].max if goal&.dig(:token_budget))

          response = {
            goal: goal,
            remaining_tokens: remaining_tokens
          }

          if completion_budget_report && goal&.dig(:status) == 'complete'
            response[:completion_budget_report] = completion_budget_report
          end

          response
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
