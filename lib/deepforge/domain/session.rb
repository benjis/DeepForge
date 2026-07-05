# frozen_string_literal: true

# 文件用途：定义代理会话的领域模型和工厂方法
# 使用方法：用于创建、更新和管理代理会话的状态

module DeepForge
  module Domain
    # 代理会话：持久化的循环投影，将轮次项目历史与运行时事件日志配对
    # 会话是追加式的，作为 AppendOnlySessionLog 的重放单元
    AgentSession = Struct.new(
      :thread_id,
      :turn_id,
      :started_at,
      :updated_at,
      :items,
      :events,
      :closed,
      keyword_init: true
    )

    # 创建代理会话：初始化一个新的会话实例
    # 参数：input - 包含线程ID和轮次ID的哈希
    def self.create_agent_session(input)
      now = input[:started_at] || Time.now.utc.strftime('%FT%TZ')
      AgentSession.new(
        thread_id: input[:thread_id],
        turn_id: input[:turn_id],
        started_at: now,
        updated_at: now,
        items: [],
        events: [],
        closed: false
      )
    end

    # 追加会话项目：向会话添加新项目（去重）
    def self.append_session_item(session, item)
      return session if session.items.any? { |i| i.id == item.id }

      session.dup.tap do |s|
        s.items = session.items + [item]
        s.updated_at = Time.now.utc.strftime('%FT%TZ')
      end
    end

    # 更新会话项目：根据项目ID和补丁更新现有项目
    def self.update_session_item(session, item_id, patch)
      changed = false
      new_items = session.items.map do |item|
        if item.id == item_id
          changed = true
          merged_fields = item.to_h.merge(patch)
          item.class.new(**merged_fields)
        else
          item
        end
      end

      return session unless changed

      session.dup.tap do |s|
        s.items = new_items
        s.updated_at = Time.now.utc.strftime('%FT%TZ')
      end
    end

    # 追加会话事件：向会话添加新事件（去重）
    def self.append_session_event(session, event)
      return session if session.events.any? { |e| e.seq == event.seq }

      session.dup.tap do |s|
        s.events = session.events + [event]
        s.updated_at = Time.now.utc.strftime('%FT%TZ')
      end
    end

    # 关闭会话：将会话标记为已关闭
    def self.close_session(session)
      session.dup.tap do |s|
        s.closed = true
        s.updated_at = Time.now.utc.strftime('%FT%TZ')
      end
    end
  end
end
