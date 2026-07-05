# frozen_string_literal: true

# 文件用途：基于内存的会话存储器
# 使用方法：用于测试和默认运行时环境。维护每个线程的三种视图：
#           事件日志（用于 SSE 重放）、消息项列表（用于重建对话块）和会话投影（用于重启时恢复状态）。

module DeepForge
  module Adapters
    module InMemory
      # 基于内存的会话存储器，用于测试和默认运行时。
      #
      # 该存储器为每个线程维护三种视图：
      # - 内存事件日志（用于 SSE 重放）
      # - 内存消息项列表（用于重建对话块）
      # - 规范会话投影（用于重启时恢复状态）
      class SessionStore
        def initialize
          # 按线程 ID 存储的事件日志
          @events = {}
          # 按线程 ID 存储的消息项列表
          @items = {}
          # 按线程 ID 存储的会话投影
          @sessions = {}
        end

        # 向指定线程追加一个事件（防止重复序列号）
        # 参数：thread_id - 线程 ID，event - 事件哈希，必须包含 :seq 键
        # 返回值：void
        def append_event(thread_id, event)
          list = @events[thread_id] || []
          return if list.any? { |e| e[:seq] == event[:seq] }

          list << event
          @events[thread_id] = list
          session = @sessions[thread_id]
          return unless session

          @sessions[thread_id] = session.merge(
            events: session[:events] + [event],
            updated_at: Time.now.utc.strftime('%FT%TZ')
          )
        end

        # 向指定线程追加或更新一个消息项
        # 参数：thread_id - 线程 ID，item - 消息项哈希，必须包含 :id 键
        # 返回值：void
        def append_item(thread_id, item)
          list = @items[thread_id] || []
          existing_index = list.index { |i| i[:id] == item[:id] }

          next_list = if existing_index
                        list.map { |i| i[:id] == item[:id] ? item : i }
                      else
                        list + [item]
                      end

          @items[thread_id] = next_list
          session = @sessions[thread_id]
          return unless session

          new_items = if existing_index
                        session[:items].map { |i| i[:id] == item[:id] ? item : i }
                      else
                        session[:items] + [item]
                      end

          @sessions[thread_id] = session.merge(
            items: new_items,
            updated_at: Time.now.utc.strftime('%FT%TZ')
          )
        end

        # 完全重写指定线程的消息项列表
        # 参数：thread_id - 线程 ID，items - 新的消息项数组
        # 返回值：void
        def rewrite_items(thread_id, items)
          next_items = items.dup
          @items[thread_id] = next_items
          session = @sessions[thread_id]
          return unless session

          @sessions[thread_id] = session.merge(
            items: next_items,
            updated_at: Time.now.utc.strftime('%FT%TZ')
          )
        end

        # 更新指定线程中指定消息项的部分字段
        # 参数：thread_id - 线程 ID，item_id - 消息项 ID，patch - 要更新的字段哈希
        # 返回值：Hash 或 nil，更新后的消息项，未找到时返回 nil
        def update_item(thread_id, item_id, patch)
          list = @items[thread_id] || []
          updated = nil

          next_list = list.map do |item|
            if item[:id] == item_id
              updated = item.merge(patch)
              updated
            else
              item
            end
          end

          return nil unless updated

          @items[thread_id] = next_list
          session = @sessions[thread_id]
          if session
            @sessions[thread_id] = session.merge(
              items: next_list,
              updated_at: Time.now.utc.strftime('%FT%TZ')
            )
          end

          updated
        end

        # 加载指定线程中从某个序列号之后的所有事件（按序列号排序）
        # 参数：thread_id - 线程 ID，since_seq - 起始序列号（不含）
        # 返回值：Array<Hash>，排序后的事件列表
        def load_events_since(thread_id, since_seq)
          list = @events[thread_id] || []
          list.select { |e| e[:seq] > since_seq }
              .sort_by { |e| e[:seq] }
        end

        # 加载指定线程的所有消息项（返回副本）
        # 参数：thread_id - 线程 ID
        # 返回值：Array<Hash>，消息项列表的副本
        def load_items(thread_id)
          (@items[thread_id] || []).dup
        end

        # 加载指定线程的会话投影
        # 参数：thread_id - 线程 ID
        # 返回值：Hash 或 nil，会话投影
        def load_session(thread_id)
          @sessions[thread_id]
        end

        # 插入或更新会话投影，并初始化事件和消息项（如果尚未存在）
        # 参数：session - 会话投影哈希，必须包含 :thread_id 键
        # 返回值：void
        def upsert_session(session)
          thread_id = session[:thread_id]
          @sessions[thread_id] = session

          @events[thread_id] = session[:events].dup unless @events.key?(thread_id)

          return if @items.key?(thread_id)

          @items[thread_id] = session[:items].dup
        end

        # 获取指定线程的最高事件序列号
        # 参数：thread_id - 线程 ID
        # 返回值：Integer，最高序列号（无事件时返回 0）
        def highest_seq(thread_id)
          list = @events[thread_id] || []
          list.reduce(0) { |max, event| [max, event[:seq]].max }
        end

        # 重置内存存储，清空所有事件、消息项和会话数据
        # 返回值：void
        def reset_memory
          @events.clear
          @items.clear
          @sessions.clear
        end
      end
    end
  end
end
