# frozen_string_literal: true

# 文件用途：基于内存的事件总线
# 使用方法：用于测试和默认运行时环境。发布者通过 publish 方法发布事件，
#           订阅者通过 subscribe 方法订阅特定线程的事件。事件总线也是 SSE 重放路径的唯一数据源。

module DeepForge
  module Adapters
    module InMemory
      # 基于内存的事件总线实现，用于测试和默认运行时。订阅者只会收到其所属线程的事件。
      # 事件总线是 SSE 重放路径的唯一数据源。
      class EventBus
        def initialize
          # 按线程 ID 存储的事件列表
          @events = {}
          # 按线程 ID 存储的订阅者处理器集合
          @subscribers = {}
          # 按线程 ID 存储的下一个序列号
          @next_seq = {}
        end

        # 发布一个事件到指定线程
        # 参数：event - 事件哈希，必须包含 :thread_id 和 :seq 键
        # 返回值：void
        def publish(event)
          thread_id = event[:thread_id]
          list = @events[thread_id] || []
          list << event
          @events[thread_id] = list

          subscribers = @subscribers[thread_id]
          return unless subscribers

          subscribers.each do |handler|
            handler.call(event)
          rescue StandardError
            # Subscribers should not throw; isolate failures so publishing continues.
          end
        end

        # 订阅指定线程的事件
        # 参数：thread_id - 线程 ID，handler - 事件处理回调
        # 返回值：Proc，取消订阅的函数
        def subscribe(thread_id, handler)
          set = @subscribers[thread_id] ||= Set.new
          set.add(handler)

          proc { set.delete(handler) }
        end

        # 获取指定线程中从某个序列号之后的所有事件（用于 SSE 重放）
        # 参数：thread_id - 线程 ID，since_seq - 起始序列号（不含）
        # 返回值：Array<Hash>，事件列表
        def snapshot_since(thread_id, since_seq)
          list = @events[thread_id] || []
          list.select { |e| e[:seq] > since_seq }
        end

        # 获取指定线程的最高序列号
        # 参数：thread_id - 线程 ID
        # 返回值：Integer，最高序列号（无事件时返回 0）
        def highest_seq(thread_id)
          list = @events[thread_id] || []
          list.reduce(0) { |max, event| [max, event[:seq]].max }
        end

        # 为指定线程分配下一个序列号
        # 参数：thread_id - 线程 ID
        # 返回值：Integer，新分配的序列号
        def allocate_seq(thread_id)
          next_val = (@next_seq[thread_id] || highest_seq(thread_id)) + 1
          @next_seq[thread_id] = next_val
          next_val
        end

        # 重置事件总线，清空所有事件、订阅者和序列号
        # 返回值：void
        def reset
          @events.clear
          @subscribers.clear
          @next_seq.clear
        end
      end
    end
  end
end
