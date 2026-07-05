# frozen_string_literal: true

# 文件用途：实现事件源模式的运行时事件归约器
# 使用方法：用于从事件流重建运行时状态投影

module DeepForge
  module Domain
    # 事件源轮次状态常量：定义轮次在事件源系统中的状态
    module EventSourcedTurnStatus
      UNKNOWN = 'unknown'
      RUNNING = 'running'
      COMPLETED = 'completed'
      FAILED = 'failed'
      ABORTED = 'aborted'
    end

    # 事件源轮次投影：包含轮次的状态和项目ID列表
    EventSourcedTurnProjection = Struct.new(
      :id,
      :thread_id,
      :status,
      :started_at,
      :finished_at,
      :steering,
      :item_ids,
      keyword_init: true
    )

    # 事件源子代理运行投影：跟踪子代理的运行状态
    EventSourcedChildRunProjection = Struct.new(
      :child_id,
      :parent_thread_id,
      :parent_turn_id,
      :label,
      :status,
      :seq,
      :updated_at,
      :text,
      keyword_init: true
    )

    # 事件源运行时投影：包含完整的运行时状态，包括线程、轮次、项目、用量等
    EventSourcedRuntimeProjection = Struct.new(
      :thread_id,
      :last_seq,
      :started_at,
      :updated_at,
      :title,
      :thread_status,
      :turns,
      :items,
      :usage,
      :child_runs,
      :compactions,
      :tool_catalog,
      :errors,
      keyword_init: true
    )

    # 工具目录投影：跟踪工具目录的变更状态
    ToolCatalogProjection = Struct.new(
      :fingerprint,
      :tool_count,
      :change_kind,
      :tool_names,
      :message,
      keyword_init: true
    )

    # 压缩投影：记录上下文压缩操作的结果
    CompactionProjection = Struct.new(
      :item_id,
      :turn_id,
      :summary,
      :replaced_tokens,
      :pinned_constraints,
      :source_digest,
      :digest_marker,
      :source_item_ids,
      keyword_init: true
    )

    # 错误投影：记录运行时发生的错误
    ErrorProjection = Struct.new(
      :seq,
      :turn_id,
      :item_id,
      :message,
      :code,
      keyword_init: true
    )

    # 创建空的运行时事件投影：初始化所有字段为默认值
    def self.create_runtime_event_projection(thread_id: '')
      EventSourcedRuntimeProjection.new(
        thread_id: thread_id,
        last_seq: 0,
        turns: [],
        items: [],
        usage: Contracts.empty_usage_snapshot,
        child_runs: [],
        compactions: [],
        errors: []
      )
    end

    # 重放运行时事件：将事件流归约为最终状态投影
    # 参数：events - 事件数组；initial - 初始投影（可选）
    def self.replay_runtime_events(events, initial: nil)
      initial ||= create_runtime_event_projection(thread_id: events.first&.thread_id || '')
      events.sort_by(&:seq).reduce(initial) { |proj, event| apply_runtime_event(proj, event) }
    end

    # 应用单个运行时事件到投影：根据事件类型更新投影状态
    def self.apply_runtime_event(projection, event)
      return projection if event.seq <= projection.last_seq

      next_proj = clone_projection(projection)
      next_proj.thread_id ||= event.thread_id
      next_proj.last_seq = event.seq
      next_proj.updated_at = event.timestamp

      case event.kind
      when 'thread_created', 'thread_updated'
        next_proj.title = event.title if event.title
        next_proj.thread_status = event.status if event.status
        next_proj.started_at ||= event.timestamp if event.kind == 'thread_created'
      when 'turn_started', 'turn_completed', 'turn_failed', 'turn_aborted', 'turn_steered'
        apply_turn_event(next_proj, event)
      when 'item_created', 'item_updated', 'item_completed', 'tool_call_started', 'tool_call_finished'
        upsert_item(next_proj, event.item, :replace)
      when 'assistant_text_delta', 'assistant_reasoning_delta'
        upsert_item(next_proj, event.item, :append_delta)
      when 'approval_requested', 'approval_resolved'
        upsert_approval_from_event(next_proj, event)
      when 'user_input_requested', 'user_input_resolved'
        upsert_user_input_from_event(next_proj, event)
      when 'compaction_started', 'compaction_completed'
        apply_compaction_event(next_proj, event)
      when 'tool_catalog_changed'
        next_proj.tool_catalog = ToolCatalogProjection.new(
          fingerprint: event.fingerprint,
          tool_count: event.tool_count,
          change_kind: event.change_kind,
          tool_names: event.tool_names,
          message: event.message
        )
      when 'usage'
        next_proj.usage = Usage.add_usage(next_proj.usage, event.usage)
      when 'error'
        next_proj.errors << ErrorProjection.new(
          seq: event.seq,
          turn_id: event.turn_id,
          item_id: event.item_id,
          message: event.message,
          code: event.code
        )
        if event.item_id && event.turn_id
          upsert_item(next_proj, Contracts::ErrorTurnItem.new(
                                   id: event.item_id,
                                   turn_id: event.turn_id,
                                   thread_id: event.thread_id,
                                   role: Contracts::TurnItemRole::SYSTEM,
                                   status: Contracts::TurnItemStatus::FAILED,
                                   created_at: event.timestamp,
                                   finished_at: event.timestamp,
                                   kind: 'error',
                                   message: event.message,
                                   code: event.code
                                 ), :replace)
        end
      end

      freeze_projection(next_proj)
    end

    # 应用轮次事件：更新轮次状态或子代理运行状态
    def self.apply_turn_event(projection, event)
      if event.child
        upsert_child_run(projection, event)
        return
      end
      return unless event.turn_id

      turn = ensure_turn(projection, event.thread_id, event.turn_id)
      case event.kind
      when 'turn_started'
        turn.status = EventSourcedTurnStatus::RUNNING
        turn.started_at ||= event.timestamp
      when 'turn_completed'
        turn.status = EventSourcedTurnStatus::COMPLETED
        turn.finished_at = event.timestamp
      when 'turn_failed'
        turn.status = EventSourcedTurnStatus::FAILED
        turn.finished_at = event.timestamp
      when 'turn_aborted'
        turn.status = EventSourcedTurnStatus::ABORTED
        turn.finished_at = event.timestamp
      when 'turn_steered'
        turn.steering << event.text if event.text
      end
    end

    # 插入或更新子代理运行记录
    def self.upsert_child_run(projection, event)
      child = event.child
      return unless child

      existing_index = projection.child_runs.index { |run| run.child_id == child.child_id }
      next_run = EventSourcedChildRunProjection.new(
        child_id: child.child_id,
        parent_thread_id: child.parent_thread_id,
        parent_turn_id: child.parent_turn_id,
        label: child.child_label,
        status: child.child_status,
        seq: child.child_seq,
        updated_at: event.timestamp,
        text: event.text
      )

      if existing_index
        projection.child_runs[existing_index] = next_run
      else
        projection.child_runs << next_run
      end
    end

    # 应用压缩事件：记录压缩操作并更新压缩项目
    def self.apply_compaction_event(projection, event)
      projection.compactions << CompactionProjection.new(
        item_id: event.item_id,
        turn_id: event.turn_id,
        summary: event.summary,
        replaced_tokens: event.replaced_tokens,
        pinned_constraints: event.pinned_constraints,
        source_digest: event.source_digest,
        digest_marker: event.digest_marker,
        source_item_ids: event.source_item_ids
      )

      return if event.kind != 'compaction_completed' || !event.item_id || !event.turn_id || !event.replaced_tokens

      upsert_item(projection, Contracts::CompactionTurnItem.new(
                                id: event.item_id,
                                turn_id: event.turn_id,
                                thread_id: event.thread_id,
                                role: Contracts::TurnItemRole::SYSTEM,
                                status: Contracts::TurnItemStatus::COMPLETED,
                                created_at: event.timestamp,
                                finished_at: event.timestamp,
                                kind: 'compaction',
                                summary: event.summary || '',
                                replaced_tokens: event.replaced_tokens,
                                pinned_constraints: event.pinned_constraints || [],
                                source_digest: event.source_digest,
                                digest_marker: event.digest_marker,
                                source_item_ids: event.source_item_ids
                              ), :replace)
    end

    # 从事件插入或更新审批项目
    def self.upsert_approval_from_event(projection, event)
      return unless event.turn_id

      existing = projection.items.find { |item| item.kind == 'approval' && item.approval_id == event.approval_id }
      status = event.status

      item = if existing&.kind == 'approval'
               existing.dup.tap do |i|
                 i.status = status
                 i.finished_at = event.timestamp if status != 'pending'
               end
             else
               Contracts::ApprovalTurnItem.new(
                 id: event.item_id || "item_#{event.approval_id}",
                 turn_id: event.turn_id,
                 thread_id: event.thread_id,
                 role: Contracts::TurnItemRole::TOOL,
                 created_at: event.timestamp,
                 kind: 'approval',
                 approval_id: event.approval_id,
                 tool_name: event.tool_name,
                 summary: event.summary || '',
                 status: status,
                 finished_at: status == 'pending' ? nil : event.timestamp
               )
             end

      upsert_item(projection, item, :replace)
    end

    # 从事件插入或更新用户输入项目
    def self.upsert_user_input_from_event(projection, event)
      return unless event.turn_id

      existing = projection.items.find { |item| item.kind == 'user_input' && item.input_id == event.input_id }
      status = event.status

      item = if existing&.kind == 'user_input'
               existing.dup.tap do |i|
                 i.status = status
                 i.finished_at = event.timestamp if status != 'pending'
               end
             else
               Contracts::UserInputTurnItem.new(
                 id: event.item_id || "item_#{event.input_id}",
                 turn_id: event.turn_id,
                 thread_id: event.thread_id,
                 role: Contracts::TurnItemRole::TOOL,
                 created_at: event.timestamp,
                 kind: 'user_input',
                 input_id: event.input_id,
                 prompt: event.prompt || '',
                 questions: event.questions || [],
                 status: status,
                 finished_at: status == 'pending' ? nil : event.timestamp
               )
             end

      upsert_item(projection, item, :replace)
    end

    # 插入或更新项目：根据模式（替换或追加增量）更新项目列表
    def self.upsert_item(projection, item, mode)
      index = projection.items.index { |candidate| candidate.id == item.id }
      next_item = if index && mode == :append_delta
                    append_delta(projection.items[index], item)
                  else
                    item
                  end

      if index
        projection.items[index] = next_item
      else
        projection.items << next_item
      end

      turn = ensure_turn(projection, item.thread_id, item.turn_id)
      turn.item_ids << item.id unless turn.item_ids.include?(item.id)
    end

    # 追加增量到现有项目：用于文本流式输出的拼接
    def self.append_delta(existing, delta)
      if (existing.kind == 'assistant_text' && delta.kind == 'assistant_text') ||
         (existing.kind == 'assistant_reasoning' && delta.kind == 'assistant_reasoning')
        existing.dup.tap do |i|
          i.text = "#{existing.text}#{delta.text}"
          i.status = delta.status
          i.finished_at = delta.finished_at || existing.finished_at
        end
      else
        delta
      end
    end

    # 确保轮次存在：如果不存在则创建新的轮次投影
    def self.ensure_turn(projection, thread_id, turn_id)
      turn = projection.turns.find { |candidate| candidate.id == turn_id }
      unless turn
        turn = EventSourcedTurnProjection.new(
          id: turn_id,
          thread_id: thread_id,
          status: EventSourcedTurnStatus::UNKNOWN,
          steering: [],
          item_ids: []
        )
        projection.turns << turn
      end
      turn
    end

    # 深拷贝投影：用于不可变更新模式
    def self.clone_projection(projection)
      EventSourcedRuntimeProjection.new(
        thread_id: projection.thread_id,
        last_seq: projection.last_seq,
        started_at: projection.started_at,
        updated_at: projection.updated_at,
        title: projection.title,
        thread_status: projection.thread_status,
        turns: projection.turns.map do |turn|
          EventSourcedTurnProjection.new(
            id: turn.id,
            thread_id: turn.thread_id,
            status: turn.status,
            started_at: turn.started_at,
            finished_at: turn.finished_at,
            steering: turn.steering.dup,
            item_ids: turn.item_ids.dup
          )
        end,
        items: projection.items.map(&:dup),
        usage: projection.usage.dup,
        child_runs: projection.child_runs.map(&:dup),
        compactions: projection.compactions.map(&:dup),
        tool_catalog: projection.tool_catalog&.dup,
        errors: projection.errors.map(&:dup)
      )
    end

    # 冻结投影：当前实现为直接返回（保留扩展点）
    def self.freeze_projection(projection)
      projection
    end
  end
end
