# frozen_string_literal: true

# 文件用途：会话存储端口，提供持久化每线程活动的功能
# 使用方法：继承此类并实现所有方法，存储包含运行时事件日志、对话项历史和完整会话投影三个流

module DeepForge
  module Ports
    # @abstract Subclass and implement all methods
    # Port for persisted per-thread activity.
    #
    # The store keeps three streams: the ordered runtime event log
    # (used by SSE replay), the turn item history (used to rebuild chat
    # blocks), and the full session projection. Implementations append to
    # JSONL and keep a small in-memory window for fast access.

    # 类功能：会话存储端口基类，定义持久化存储接口
    class SessionStore
      # 方法功能：追加运行时事件到线程事件日志
      # 参数：thread_id - 线程ID，event - 运行时事件对象
      # 使用方法：传入线程ID和事件对象，追加到事件日志
      # @param thread_id [String]
      # @param event [Contracts::RuntimeEvent]
      def append_event(thread_id, event)
        raise NotImplementedError
      end

      # 方法功能：追加对话项到线程历史
      # 参数：thread_id - 线程ID，item - 对话项对象
      # 使用方法：传入线程ID和对话项，追加到历史记录
      # @param thread_id [String]
      # @param item [Contracts::TurnItem]
      def append_item(thread_id, item)
        raise NotImplementedError
      end

      # 方法功能：替换线程的规范对话项流
      # 参数：thread_id - 线程ID，items - 新的对话项数组
      # 使用方法：传入线程ID和新对话项数组，原子性替换存储
      # @param thread_id [String]
      # @param items [Array<Contracts::TurnItem>]
      def rewrite_items(thread_id, items)
        raise NotImplementedError
      end

      # 方法功能：更新指定对话项
      # 参数：thread_id - 线程ID，item_id - 项ID，patch - 更新补丁
      # 返回值：更新后的对话项或nil
      # 使用方法：传入线程ID、项ID和更新内容
      # @param thread_id [String]
      # @param item_id [String]
      # @param patch [Hash]
      # @return [Contracts::TurnItem, nil]
      def update_item(thread_id, item_id, patch)
        raise NotImplementedError
      end

      # 方法功能：加载指定序号之后的运行时事件
      # 参数：thread_id - 线程ID，since_seq - 起始序号
      # 返回值：事件数组
      # 使用方法：传入线程ID和起始序号，返回该序号之后的事件
      # @param thread_id [String]
      # @param since_seq [Integer]
      # @return [Array<Contracts::RuntimeEvent>]
      def load_events_since(thread_id, since_seq)
        raise NotImplementedError
      end

      # 方法功能：加载线程的所有对话项
      # 参数：thread_id - 线程ID
      # 返回值：对话项数组
      # 使用方法：传入线程ID，返回该线程的所有对话项
      # @param thread_id [String]
      # @return [Array<Contracts::TurnItem>]
      def load_items(thread_id)
        raise NotImplementedError
      end

      # 方法功能：加载线程的会话状态
      # 参数：thread_id - 线程ID
      # 返回值：代理会话对象或nil
      # 使用方法：传入线程ID，返回对应的会话状态
      # @param thread_id [String]
      # @return [Domain::AgentSession, nil]
      def load_session(thread_id)
        raise NotImplementedError
      end

      # 方法功能：插入或更新会话状态
      # 参数：session - 代理会话对象
      # 使用方法：传入会话对象，创建或更新存储中的会话
      # @param session [Domain::AgentSession]
      def upsert_session(session)
        raise NotImplementedError
      end

      # 方法功能：获取线程的最高事件序号
      # 参数：thread_id - 线程ID
      # 返回值：最高序号整数，无事件时返回0
      # 使用方法：传入线程ID，返回该线程的最大事件序号
      # @param thread_id [String]
      # @return [Integer]
      def highest_seq(thread_id)
        raise NotImplementedError
      end

      # 方法功能：重置内存状态（不影响磁盘）
      # 使用方法：调用清空所有内存中的状态
      def reset_memory
        raise NotImplementedError
      end
    end
  end
end
