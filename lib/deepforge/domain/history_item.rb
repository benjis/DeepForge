# frozen_string_literal: true

# 文件用途：定义轮次项目的工厂方法
# 使用方法：用于创建各种类型的轮次项目

module DeepForge
  module Domain
    # 项目实体类型：引用轮次项目的联合类型
    HistoryItemEntity = Contracts::TurnItem

    # 创建用户项目：包含文本和可选的附件ID列表
    def self.make_user_item(input)
      attachment_ids = input[:attachment_ids]&.reject { |id| id.strip.empty? }
      display_text = input[:display_text]&.strip

      Contracts::UserTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::USER,
        status: Contracts::TurnItemStatus::COMPLETED,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        finished_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'user_message',
        text: input[:text],
        display_text: display_text && display_text != input[:text] ? display_text : nil,
        attachment_ids: attachment_ids&.any? ? attachment_ids : nil
      )
    end

    # 创建助手文本项目：助手生成的文本回复
    def self.make_assistant_text_item(input)
      Contracts::AssistantTextTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::ASSISTANT,
        status: input[:status] || Contracts::TurnItemStatus::RUNNING,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'assistant_text',
        text: input[:text]
      )
    end

    # 创建助手推理项目：助手的推理过程文本
    def self.make_assistant_reasoning_item(input)
      Contracts::AssistantReasoningTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::ASSISTANT,
        status: input[:status] || Contracts::TurnItemStatus::RUNNING,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'assistant_reasoning',
        text: input[:text]
      )
    end

    # 创建工具调用项目：记录工具调用的请求信息
    def self.make_tool_call_item(input)
      Contracts::ToolCallTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::TOOL,
        status: input[:status] || Contracts::TurnItemStatus::PENDING,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'tool_call',
        tool_name: input[:tool_name],
        call_id: input[:call_id],
        tool_kind: input[:tool_kind] || Contracts::ToolKind::TOOL_CALL,
        arguments: input[:arguments],
        summary: input[:summary]
      )
    end

    # 创建工具结果项目：记录工具调用的执行结果
    def self.make_tool_result_item(input)
      status = input[:status] || Contracts::TurnItemStatus::COMPLETED
      finished_at = input[:finished_at] || if %w[completed failed aborted].include?(status)
                                             Time.now.utc.strftime('%FT%TZ')
                                           end

      Contracts::ToolResultTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::TOOL,
        status: status,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        finished_at: finished_at,
        kind: 'tool_result',
        tool_name: input[:tool_name],
        call_id: input[:call_id],
        tool_kind: input[:tool_kind] || Contracts::ToolKind::TOOL_CALL,
        output: input[:output],
        is_error: input[:is_error] || false
      )
    end

    # 创建审批项目：记录需要用户审批的工具调用
    def self.make_approval_item(input)
      Contracts::ApprovalTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::TOOL,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'approval',
        approval_id: input[:approval_id],
        tool_name: input[:tool_name],
        summary: input[:summary],
        status: Contracts::TurnItemStatus::PENDING
      )
    end

    # 创建用户输入项目：记录助手请求用户输入的问题
    def self.make_user_input_item(input)
      Contracts::UserInputTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::TOOL,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'user_input',
        input_id: input[:input_id],
        prompt: input[:prompt],
        questions: input[:questions] || [],
        status: 'pending'
      )
    end

    # 创建压缩项目：记录上下文压缩操作的结果
    def self.make_compaction_item(input)
      Contracts::CompactionTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::SYSTEM,
        status: Contracts::TurnItemStatus::COMPLETED,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        finished_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'compaction',
        summary: input[:summary],
        replaced_tokens: input[:replaced_tokens],
        pinned_constraints: input[:pinned_constraints],
        source_digest: input[:source_digest],
        digest_marker: input[:digest_marker],
        source_item_ids: input[:source_item_ids]&.dup
      )
    end

    # 创建审查项目：记录代码审查的结果
    def self.make_review_item(input)
      status = input[:status] || Contracts::TurnItemStatus::RUNNING
      finished_at = input[:finished_at] || if %w[completed failed aborted].include?(status)
                                             Time.now.utc.strftime('%FT%TZ')
                                           end

      Contracts::ReviewTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::ASSISTANT,
        status: status,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        finished_at: finished_at,
        kind: 'review',
        target: input[:target],
        title: input[:title],
        review_text: input[:review_text],
        output: input[:output]
      )
    end

    # 创建错误项目：记录运行时发生的错误
    def self.make_error_item(input)
      Contracts::ErrorTurnItem.new(
        id: input[:id],
        turn_id: input[:turn_id],
        thread_id: input[:thread_id],
        role: Contracts::TurnItemRole::SYSTEM,
        status: Contracts::TurnItemStatus::FAILED,
        created_at: Time.now.utc.strftime('%FT%TZ'),
        finished_at: Time.now.utc.strftime('%FT%TZ'),
        kind: 'error',
        message: input[:message],
        code: input[:code]
      )
    end
  end
end
