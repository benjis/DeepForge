# frozen_string_literal: true

# 文件用途：事件总线端口，用于将运行时事件分发给订阅者（主要是SSE端点）
# 使用方法：继承此类并实现所有方法，总线是内存中同步的，HTTP层使用since_seq重放恢复

module DeepForge
  module Ports
    # @abstract Subclass and implement all methods
    # Port for fanning out runtime events to subscribers (mostly the SSE
    # endpoint). The bus is in-memory and synchronous; the HTTP layer
    # replays the bus with `since_seq` to recover after reconnects.

    # 类功能：事件总线端口基类，定义事件发布订阅接口
    class EventBus
      # 方法功能：发布运行时事件
      # 参数：event - 运行时事件对象
      # 使用方法：传入事件对象，分发给所有订阅者
      # @param event [Contracts::RuntimeEvent]
      def publish(event)
        raise NotImplementedError
      end

      # 方法功能：订阅指定线程的事件
      # 参数：thread_id - 线程ID，handler - 事件处理回调函数
      # 返回值：取消订阅函数
      # 使用方法：传入线程ID和处理函数，返回取消订阅的Proc
      # @param thread_id [String]
      # @param handler [Proc]
      # @return [Proc] unsubscribe function
      def subscribe(thread_id, handler)
        raise NotImplementedError
      end

      # 方法功能：获取指定序号之后的所有事件快照
      # 参数：thread_id - 线程ID，since_seq - 起始序号
      # 返回值：事件数组
      # 使用方法：传入线程ID和起始序号，返回该序号之后的所有事件
      # @param thread_id [String]
      # @param since_seq [Integer]
      # @return [Array<Contracts::RuntimeEvent>]
      def snapshot_since(thread_id, since_seq)
        raise NotImplementedError
      end

      # 方法功能：获取指定线程的最高事件序号
      # 参数：thread_id - 线程ID
      # 返回值：最高序号整数
      # 使用方法：传入线程ID，返回该线程的最大事件序号
      # @param thread_id [String]
      # @return [Integer]
      def highest_seq(thread_id)
        raise NotImplementedError
      end

      # 方法功能：重置事件总线状态
      # 使用方法：调用清空所有事件和订阅状态
      def reset
        raise NotImplementedError
      end
    end
  end
end
