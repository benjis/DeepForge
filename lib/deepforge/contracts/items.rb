# frozen_string_literal: true

# 文件用途：定义轮次项目（Turn Item）的数据结构
# 使用方法：用于存储和传输对话轮次中的各种项目类型

module DeepForge
  module Contracts
    # 轮次项目角色常量：定义项目在对话中的角色
    module TurnItemRole
      USER = 'user'
      ASSISTANT = 'assistant'
      SYSTEM = 'system'
      TOOL = 'tool'
    end

    # 轮次项目状态常量：定义项目的生命周期状态
    module TurnItemStatus
      PENDING = 'pending'
      RUNNING = 'running'
      COMPLETED = 'completed'
      FAILED = 'failed'
      ABORTED = 'aborted'
    end

    # 工具类型常量：定义工具调用的种类
    module ToolKind
      TOOL_CALL = 'tool_call'
      COMMAND_EXECUTION = 'command_execution'
      FILE_CHANGE = 'file_change'
    end

    # 所有轮次项目的基础字段：包含ID、角色、状态和时间戳
    TurnItemBase = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      keyword_init: true
    )

    # 用户输入选项：用于用户输入问题中的选项
    UserInputOption = Struct.new(
      :label,
      :description,
      keyword_init: true
    )

    # 用户输入问题：包含标题、问题内容和选项列表
    UserInputQuestion = Struct.new(
      :header,
      :id,
      :question,
      :options,
      keyword_init: true
    )

    # 用户轮次项目：用户发送的消息，包含文本和附件
    UserTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :text,
      :display_text,
      :attachment_ids,
      keyword_init: true
    )

    # 助手文本轮次项目：助手生成的文本回复
    AssistantTextTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :text,
      keyword_init: true
    )

    # 助手推理轮次项目：助手的推理过程文本
    AssistantReasoningTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :text,
      keyword_init: true
    )

    # 工具调用轮次项目：助手发起的工具调用请求
    ToolCallTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :tool_name,
      :call_id,
      :tool_kind,
      :arguments,
      :summary,
      keyword_init: true
    )

    # 工具结果轮次项目：工具调用的执行结果
    ToolResultTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :tool_name,
      :call_id,
      :tool_kind,
      :output,
      :is_error,
      keyword_init: true
    )

    # 审批轮次项目：需要用户审批的工具调用
    ApprovalTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :approval_id,
      :tool_name,
      :summary,
      keyword_init: true
    )

    # 用户输入轮次项目：助手请求用户提供额外输入
    UserInputTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :input_id,
      :prompt,
      :questions,
      keyword_init: true
    )

    # 上下文压缩轮次项目：记录上下文压缩操作的结果
    CompactionTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :summary,
      :replaced_tokens,
      :pinned_constraints,
      :source_digest,
      :digest_marker,
      :source_item_ids,
      keyword_init: true
    )

    # 代码审查轮次项目：代码审查操作的结果
    ReviewTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :target,
      :title,
      :review_text,
      :output,
      keyword_init: true
    )

    # 错误轮次项目：记录运行时发生的错误
    ErrorTurnItem = Struct.new(
      :id,
      :turn_id,
      :thread_id,
      :role,
      :status,
      :created_at,
      :finished_at,
      :kind,
      :message,
      :code,
      keyword_init: true
    )

    # TurnItem 联合类型：包含所有可能的轮次项目类型
    TurnItem = [
      UserTurnItem,
      AssistantTextTurnItem,
      AssistantReasoningTurnItem,
      ToolCallTurnItem,
      ToolResultTurnItem,
      ApprovalTurnItem,
      UserInputTurnItem,
      CompactionTurnItem,
      ReviewTurnItem,
      ErrorTurnItem
    ].freeze
  end
end
