# frozen_string_literal: true

# 文件用途：定义线程记录的领域模型和工厂方法
# 使用方法：用于创建线程记录、更新时间戳和生成线程摘要

module DeepForge
  module Domain
    # 线程实体类型：引用线程记录的契约类型
    AgentThreadEntity = Contracts::ThreadRecord

    # 创建线程记录：初始化一个新的线程实例，设置默认值
    # 参数：input - 包含标题、工作空间、模型等信息的哈希
    def self.create_thread_record(input)
      now = input[:created_at] || Time.now.utc.strftime('%FT%TZ')
      Contracts::ThreadRecord.new(
        id: input[:id],
        title: input[:title],
        workspace: input[:workspace],
        model: input[:model],
        mode: input[:mode] || Contracts::ThreadMode::AGENT,
        status: input[:status] || Contracts::ThreadStatus::IDLE,
        approval_policy: input[:approval_policy] || Contracts::ApprovalPolicy::ON_REQUEST,
        sandbox_mode: input[:sandbox_mode] || Contracts::SandboxMode::WORKSPACE_WRITE,
        cost_budget_usd: input[:cost_budget_usd],
        cost_budget_warning_sent: input[:cost_budget_warning_sent],
        relation: input[:relation] || Contracts::ThreadRelation::PRIMARY,
        parent_thread_id: input[:parent_thread_id],
        forked_from_thread_id: input[:forked_from_thread_id],
        forked_from_title: input[:forked_from_title],
        forked_at: input[:forked_at],
        forked_from_message_count: input[:forked_from_message_count],
        forked_from_turn_count: input[:forked_from_turn_count],
        goal: input[:goal],
        todos: input[:todos],
        created_at: now,
        updated_at: now,
        turns: []
      )
    end

    # 更新线程时间戳：将线程的更新时间设置为当前时间
    def self.touch_thread(thread, updated_at: nil)
      thread.dup.tap { |t| t.updated_at = updated_at || Time.now.utc.strftime('%FT%TZ') }
    end

    # 转换为线程摘要：从完整线程记录生成精简的摘要视图
    def self.to_thread_summary(thread)
      Contracts::ThreadSummary.new(
        id: thread.id,
        title: thread.title,
        workspace: thread.workspace,
        model: thread.model,
        mode: thread.mode,
        status: thread.status,
        cost_budget_usd: thread.cost_budget_usd,
        cost_budget_warning_sent: thread.cost_budget_warning_sent,
        relation: thread.relation,
        parent_thread_id: thread.parent_thread_id,
        forked_from_thread_id: thread.forked_from_thread_id,
        forked_from_title: thread.forked_from_title,
        forked_at: thread.forked_at,
        forked_from_message_count: thread.forked_from_message_count,
        forked_from_turn_count: thread.forked_from_turn_count,
        goal: thread.goal,
        todos: thread.todos,
        created_at: thread.created_at,
        updated_at: thread.updated_at
      )
    end
  end
end
