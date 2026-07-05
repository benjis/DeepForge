# frozen_string_literal: true

# 文件用途：定义线程（Thread）相关的请求、响应和数据结构
# 使用方法：用于线程的创建、更新、查询、删除和目标/待办事项管理

module DeepForge
  module Contracts
    # 线程状态常量：定义线程的生命周期状态
    module ThreadStatus
      IDLE = 'idle'
      RUNNING = 'running'
      ARCHIVED = 'archived'
      DELETED = 'deleted'
    end

    # 线程模式常量：定义线程的工作模式
    module ThreadMode
      AGENT = 'agent'
      PLAN = 'plan'
    end

    # 线程关系类型：定义线程之间的关系（主分支、分叉、旁路）
    module ThreadRelation
      PRIMARY = 'primary'
      FORK = 'fork'
      SIDE = 'side'
    end

    # 线程目标状态常量：定义目标的当前状态
    module ThreadGoalStatus
      ACTIVE = 'active'
      PAUSED = 'paused'
      BLOCKED = 'blocked'
      USAGE_LIMITED = 'usageLimited'
      BUDGET_LIMITED = 'budgetLimited'
      COMPLETE = 'complete'
    end

    # 目标描述的最大字符数限制
    MAX_THREAD_GOAL_OBJECTIVE_CHARS = 4_000

    # 线程目标：包含目标描述、状态、预算和用量信息
    ThreadGoal = Struct.new(
      :thread_id,
      :objective,
      :status,
      :token_budget,
      :tokens_used,
      :time_used_seconds,
      :created_at,
      :updated_at,
      keyword_init: true
    )

    # 待办事项状态常量：定义待办事项的生命周期状态
    module ThreadTodoStatus
      PENDING = 'pending'
      IN_PROGRESS = 'in_progress'
      COMPLETED = 'completed'
    end

    # 待办事项来源：记录待办事项的创建来源
    ThreadTodoSource = Struct.new(
      :kind,
      :plan_id,
      :relative_path,
      :ordinal,
      :content_hash,
      keyword_init: true
    )

    # 待办事项内容的最大字符数限制
    MAX_THREAD_TODO_CONTENT_CHARS = 1_000
    # 单个线程的最大待办事项数
    MAX_THREAD_TODOS = 200

    # 待办事项条目：包含ID、内容、状态和来源
    ThreadTodoItem = Struct.new(
      :id,
      :content,
      :status,
      :source,
      :created_at,
      :updated_at,
      keyword_init: true
    )

    # 待办事项列表：包含线程ID、条目数组和更新时间
    ThreadTodoList = Struct.new(
      :thread_id,
      :items,
      :updated_at,
      keyword_init: true
    )

    # 验证待办事项列表：确保最多只有一个待办事项处于进行中状态
    def self.validate_todo_list(list)
      in_progress_count = list.items.count { |i| i.status == ThreadTodoStatus::IN_PROGRESS }
      raise ArgumentError, 'at most one todo can be in_progress' if in_progress_count > 1
    end

    # 线程记录：存储线程的完整信息，包括标题、工作空间、模型、策略等
    ThreadRecord = Struct.new(
      :id,
      :title,
      :workspace,
      :model,
      :mode,
      :status,
      :approval_policy,
      :sandbox_mode,
      :cost_budget_usd,
      :cost_budget_warning_sent,
      :relation,
      :parent_thread_id,
      :forked_from_thread_id,
      :forked_from_title,
      :forked_at,
      :forked_from_message_count,
      :forked_from_turn_count,
      :goal,
      :todos,
      :created_at,
      :updated_at,
      :turns,
      keyword_init: true
    )

    # 线程摘要：线程的精简视图，用于列表展示
    ThreadSummary = Struct.new(
      :id,
      :title,
      :workspace,
      :model,
      :mode,
      :status,
      :cost_budget_usd,
      :cost_budget_warning_sent,
      :relation,
      :parent_thread_id,
      :forked_from_thread_id,
      :forked_from_title,
      :forked_at,
      :forked_from_message_count,
      :forked_from_turn_count,
      :goal,
      :todos,
      :created_at,
      :updated_at,
      keyword_init: true
    )

    # 创建线程请求：包含标题、工作空间、模型、模式等参数
    CreateThreadRequest = Struct.new(
      :title,
      :workspace,
      :model,
      :mode,
      :approval_policy,
      :sandbox_mode,
      :cost_budget_usd,
      keyword_init: true
    )

    # 分叉线程请求：从现有线程创建新线程
    ForkThreadRequest = Struct.new(
      :relation,
      :title,
      keyword_init: true
    )

    # 设置线程目标请求：包含目标描述、状态和 token 预算
    SetThreadGoalRequest = Struct.new(
      :objective,
      :status,
      :token_budget,
      keyword_init: true
    ) do
      def self.validate(attrs)
        obj = attrs.is_a?(Hash) ? new(**attrs) : attrs
        return true if obj.objective || obj.status || obj.token_budget

        raise ArgumentError, 'At least one of objective, status, or tokenBudget must be provided'
      end
    end

    # 线程目标响应：返回设置的目标信息
    ThreadGoalResponse = Struct.new(
      :goal,
      keyword_init: true
    )

    # 清除线程目标响应：返回清除操作结果
    ClearThreadGoalResponse = Struct.new(
      :cleared,
      keyword_init: true
    )

    # 设置线程待办事项请求：包含待办事项列表
    SetThreadTodosRequest = Struct.new(
      :todos,
      keyword_init: true
    ) do
      def self.validate(attrs)
        obj = attrs.is_a?(Hash) ? new(**attrs) : attrs
        return true unless obj.todos.is_a?(Array)

        in_progress_count = obj.todos.count do |t|
          t.is_a?(Hash) ? t['status'] == 'in_progress' : t.status == 'in_progress'
        end
        return true if in_progress_count <= 1

        raise ArgumentError, 'At most one todo can be in_progress'
      end
    end

    # 线程待办事项响应：返回待办事项列表
    ThreadTodosResponse = Struct.new(
      :todos,
      keyword_init: true
    )

    # 清除线程待办事项响应：返回清除操作结果
    ClearThreadTodosResponse = Struct.new(
      :cleared,
      keyword_init: true
    )

    # 更新线程请求：可更新标题、状态、策略等字段
    UpdateThreadRequest = Struct.new(
      :title,
      :status,
      :approval_policy,
      :sandbox_mode,
      :cost_budget_usd,
      :cost_budget_warning_sent,
      :relation,
      keyword_init: true
    ) do
      def self.validate(attrs)
        obj = attrs.is_a?(Hash) ? new(**attrs) : attrs
        return true if obj.title || obj.status || obj.approval_policy || obj.sandbox_mode ||
                       obj.cost_budget_usd || obj.cost_budget_warning_sent || obj.relation

        raise ArgumentError, 'At least one field must be provided'
      end
    end

    # 线程列表响应：返回线程摘要数组
    ListThreadsResponse = Struct.new(
      :threads,
      keyword_init: true
    )

    # 删除线程响应：返回删除操作结果
    DeleteThreadResponse = Struct.new(
      :id,
      :deleted,
      keyword_init: true
    )
  end
end
