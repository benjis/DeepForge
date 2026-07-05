# frozen_string_literal: true

# 文件用途：定义轮次（Turn）相关的请求、响应和数据结构
# 使用方法：用于轮次的启动、引导、中断和上下文压缩

module DeepForge
  module Contracts
    # 轮次推理努力常量：定义模型推理的详细程度
    module TurnReasoningEffort
      AUTO = 'auto'
      OFF = 'off'
      LOW = 'low'
      MEDIUM = 'medium'
      HIGH = 'high'
      MAX = 'max'
    end

    # GUI 计划操作常量：定义计划的创建和优化操作
    module GuiPlanOperation
      DRAFT = 'draft'
      REFINE = 'refine'
    end

    # GUI 计划上下文：包含计划操作类型和相关参数
    GuiPlanContext = Struct.new(
      :operation,
      :workspace_root,
      :relative_path,
      :plan_id,
      :source_request,
      :title,
      keyword_init: true
    )

    # 轮次状态常量：定义轮次的生命周期状态
    module TurnStatus
      QUEUED = 'queued'
      RUNNING = 'running'
      COMPLETED = 'completed'
      FAILED = 'failed'
      ABORTED = 'aborted'
    end

    # 轮次记录：存储轮次的完整信息，包括提示、模型、状态和项目列表
    Turn = Struct.new(
      :id,
      :thread_id,
      :status,
      :prompt,
      :model,
      :reasoning_effort,
      :steering,
      :created_at,
      :started_at,
      :finished_at,
      :items,
      :attachment_ids,
      :active_skill_ids,
      :injected_memory_ids,
      :skill_injection_bytes,
      :tool_catalog_fingerprint,
      :tool_catalog_tool_count,
      :tool_catalog_drift,
      :gui_plan,
      :mode,
      :error,
      keyword_init: true
    )

    # 启动轮次请求：包含提示文本、模型、推理努力等参数
    StartTurnRequest = Struct.new(
      :prompt,
      :display_text,
      :model,
      :reasoning_effort,
      :approval_policy,
      :mode,
      :attachments,
      :attachment_ids,
      :gui_plan,
      keyword_init: true
    )

    # 启动轮次响应：返回线程ID、轮次ID和用户消息项目ID
    StartTurnResponse = Struct.new(
      :thread_id,
      :turn_id,
      :user_message_item_id,
      keyword_init: true
    )

    # 引导轮次请求：在轮次运行中发送引导文本
    SteerTurnRequest = Struct.new(
      :text,
      keyword_init: true
    )

    # 中断轮次请求：中断正在运行的轮次
    InterruptTurnRequest = Struct.new(
      :discard,
      keyword_init: true
    )

    # 中断轮次响应：返回中断操作结果
    InterruptTurnResponse = Struct.new(
      :thread_id,
      :turn_id,
      :status,
      keyword_init: true
    )

    # 上下文压缩请求：触发上下文压缩操作
    CompactRequest = Struct.new(
      :reason,
      :budget_tokens,
      keyword_init: true
    )

    # 上下文压缩响应：返回压缩结果，包括替换的 token 数和摘要
    CompactResponse = Struct.new(
      :thread_id,
      :replaced_tokens,
      :summary,
      :pinned_constraints,
      :source_digest,
      :digest_marker,
      :source_item_ids,
      keyword_init: true
    )
  end
end
