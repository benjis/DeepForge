# frozen_string_literal: true

# 文件用途：定义轮次的领域模型和工厂方法
# 使用方法：用于创建轮次记录、管理轮次项目和控制轮次生命周期

module DeepForge
  module Domain
    # 轮次实体类型：引用轮次契约类型
    DialogueTurnEntity = Contracts::Turn

    # 创建轮次记录：初始化一个新的轮次实例
    # 参数：input - 包含线程ID、提示文本、模型等信息的哈希
    def self.create_turn_record(input)
      model = input[:model]&.strip
      reasoning_effort = normalize_reasoning_effort(input[:reasoning_effort])

      Contracts::Turn.new(
        id: input[:id],
        thread_id: input[:thread_id],
        status: input[:status] || Contracts::TurnStatus::QUEUED,
        prompt: input[:prompt],
        steering: [],
        items: [],
        attachment_ids: input[:attachment_ids]&.dup || [],
        active_skill_ids: [],
        injected_memory_ids: [],
        model: model,
        reasoning_effort: reasoning_effort,
        gui_plan: input[:gui_plan],
        mode: input[:mode],
        created_at: input[:created_at] || Time.now.utc.strftime('%FT%TZ')
      )
    end

    # 追加轮次项目：向轮次添加新项目（去重，相同ID则替换）
    def self.append_turn_item(turn, item)
      existing_index = turn.items.index { |i| i.id == item.id }
      if existing_index
        new_items = turn.items.dup
        new_items[existing_index] = item
        turn.dup.tap { |t| t.items = new_items }
      else
        turn.dup.tap { |t| t.items = turn.items + [item] }
      end
    end

    # 替换轮次项目：根据项目ID和补丁更新现有项目
    def self.replace_turn_item(turn, item_id, patch)
      new_items = turn.items.map do |existing|
        if existing.id == item_id
          # Merge patch into existing item
          merged_fields = existing.to_h.merge(patch)
          existing.class.new(**merged_fields)
        else
          existing
        end
      end
      turn.dup.tap { |t| t.items = new_items }
    end

    # 启动轮次：将轮次状态设置为运行中
    def self.start_turn(turn, started_at: nil)
      turn.dup.tap do |t|
        t.status = Contracts::TurnStatus::RUNNING
        t.started_at = started_at || Time.now.utc.strftime('%FT%TZ')
      end
    end

    # 完成轮次：将轮次设置为指定状态并记录完成时间
    def self.finish_turn(turn, status, finished_at: nil)
      turn.dup.tap do |t|
        t.status = status
        t.finished_at = finished_at || Time.now.utc.strftime('%FT%TZ')
        t.steering = []
      end
    end

    # 标准化推理努力值：将 "auto" 或 nil 转换为 nil
    def self.normalize_reasoning_effort(effort)
      effort && effort != 'auto' ? effort : nil
    end
  end
end
