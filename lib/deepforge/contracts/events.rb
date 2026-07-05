# frozen_string_literal: true

# 文件用途：定义运行时事件的类型和数据结构
# 使用方法：用于 SSE 事件流、事件重放和事件源系统

module DeepForge
  module Contracts
    # 运行时事件类型常量：定义所有可能的事件种类
    module RuntimeEventKind
      THREAD_CREATED = 'thread_created'
      THREAD_UPDATED = 'thread_updated'
      TURN_STARTED = 'turn_started'
      TURN_COMPLETED = 'turn_completed'
      TURN_FAILED = 'turn_failed'
      TURN_ABORTED = 'turn_aborted'
      TURN_STEERED = 'turn_steered'
      ITEM_CREATED = 'item_created'
      ITEM_UPDATED = 'item_updated'
      ITEM_COMPLETED = 'item_completed'
      ASSISTANT_TEXT_DELTA = 'assistant_text_delta'
      ASSISTANT_REASONING_DELTA = 'assistant_reasoning_delta'
      TOOL_CALL_READY = 'tool_call_ready'
      TOOL_RESULT_UPLOAD_WAIT = 'tool_result_upload_wait'
      TOOL_STORM_SUPPRESSED = 'tool_storm_suppressed'
      TOOL_CATALOG_CHANGED = 'tool_catalog_changed'
      TOOL_CALL_STARTED = 'tool_call_started'
      TOOL_CALL_FINISHED = 'tool_call_finished'
      APPROVAL_REQUESTED = 'approval_requested'
      APPROVAL_RESOLVED = 'approval_resolved'
      USER_INPUT_REQUESTED = 'user_input_requested'
      USER_INPUT_RESOLVED = 'user_input_resolved'
      COMPACTION_STARTED = 'compaction_started'
      COMPACTION_COMPLETED = 'compaction_completed'
      GOAL_UPDATED = 'goal_updated'
      GOAL_CLEARED = 'goal_cleared'
      TODOS_UPDATED = 'todos_updated'
      TODOS_CLEARED = 'todos_cleared'
      PIPELINE_STAGE = 'pipeline_stage'
      USAGE = 'usage'
      ERROR = 'error'
      HEARTBEAT = 'heartbeat'
    end

    # 管道阶段常量：定义请求处理管道的各个阶段
    module PipelineStage
      SETUP = 'setup'
      PRE_START = 'pre_start'
      POST_START = 'post_start'
      INPUT_RECEIVED = 'input_received'
      INPUT_CACHED = 'input_cached'
      INPUT_ROUTED = 'input_routed'
      INPUT_COMPRESSED = 'input_compressed'
      INPUT_REMEMBERED = 'input_remembered'
      PRE_SEND = 'pre_send'
      POST_SEND = 'post_send'
      RESPONSE_RECEIVED = 'response_received'
    end

    # 运行时事件基础字段：所有事件共有的字段
    RuntimeEventBase = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      keyword_init: true
    )

    # 子代理事件字段：描述子代理运行的相关信息
    RuntimeEventChild = Struct.new(
      :parent_thread_id,
      :parent_turn_id,
      :child_id,
      :child_label,
      :child_status,
      :child_seq,
      keyword_init: true
    )

    # 项目事件：项目创建、更新、完成时触发
    ItemEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :item,
      keyword_init: true
    )

    # 线程生命周期事件：线程创建或更新时触发
    ThreadLifecycleEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :title,
      :status,
      keyword_init: true
    )

    # 轮次生命周期事件：轮次启动、完成、失败、中止或引导时触发
    TurnLifecycleEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :status,
      :text,
      :message,
      keyword_init: true
    )

    # 审批事件：审批请求或审批解决时触发
    ApprovalEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :approval_id,
      :tool_name,
      :status,
      :summary,
      keyword_init: true
    )

    # 用户输入事件：用户输入请求或解决时触发
    UserInputEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :input_id,
      :status,
      :prompt,
      :questions,
      keyword_init: true
    )

    # 工具调用就绪事件：工具调用准备就绪时触发
    ToolCallReadyEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :tool_name,
      :call_id,
      :ready_count,
      keyword_init: true
    )

    # 工具上传状态事件：工具结果上传等待时触发
    ToolUploadStatusEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :status,
      :tool_result_count,
      keyword_init: true
    )

    # 工具风暴抑制事件：工具调用被限流抑制时触发
    ToolStormSuppressedEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :tool_name,
      :call_id,
      :message,
      keyword_init: true
    )

    # 工具目录变更事件：工具目录发生变更时触发
    ToolCatalogEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :fingerprint,
      :tool_count,
      :change_kind,
      :tool_names,
      :message,
      keyword_init: true
    )

    # 上下文压缩事件：上下文压缩开始或完成时触发
    CompactionEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :summary,
      :replaced_tokens,
      :pinned_constraints,
      :source_digest,
      :digest_marker,
      :source_item_ids,
      keyword_init: true
    )

    # 目标事件：目标更新或清除时触发
    GoalEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :goal,
      :cleared,
      keyword_init: true
    )

    # 待办事项事件：待办事项更新或清除时触发
    TodoEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :todos,
      :cleared,
      keyword_init: true
    )

    # 用量事件：模型响应返回用量数据时触发
    UsageEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :model,
      :usage,
      keyword_init: true
    )

    # 管道阶段事件：请求处理管道进入新阶段时触发
    PipelineStageEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :stage,
      :label,
      :details,
      keyword_init: true
    )

    # 错误事件：运行时发生错误时触发
    ErrorEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      :message,
      :code,
      keyword_init: true
    )

    # 心跳事件：保持 SSE 连接活跃
    HeartbeatEvent = Struct.new(
      :seq,
      :timestamp,
      :thread_id,
      :turn_id,
      :item_id,
      :child,
      :kind,
      keyword_init: true
    )

    # RuntimeEvent 联合类型：包含所有可能的事件类型
    RuntimeEvent = [
      ItemEvent,
      ThreadLifecycleEvent,
      TurnLifecycleEvent,
      ApprovalEvent,
      UserInputEvent,
      ToolCallReadyEvent,
      ToolUploadStatusEvent,
      ToolStormSuppressedEvent,
      ToolCatalogEvent,
      CompactionEvent,
      GoalEvent,
      TodoEvent,
      PipelineStageEvent,
      UsageEvent,
      ErrorEvent,
      HeartbeatEvent
    ].freeze
  end
end
