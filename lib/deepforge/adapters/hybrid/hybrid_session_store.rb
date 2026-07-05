# frozen_string_literal: true

# 文件用途：混合模式会话存储适配器
# 组合文件存储和 SQLite 索引，提供带索引的会话存储功能
# 会话数据主体由 FileSessionStore 管理，索引更新在写入成功后进行
# 使用方法：HybridSessionStore.new(data_dir: '/path', index: hybrid_thread_store)

require_relative '../file/file_session_store'
require_relative 'hybrid_thread_store'

module DeepForge
  module Adapters
    module Hybrid
      # 类功能：混合模式会话存储器
      # 基于 FileSessionStore 实现数据持久化，同时维护 SQLite 索引
      class HybridSessionStore
        # 方法功能：初始化混合模式会话存储器
        # 参数：data_dir - 数据目录，index - SQLite 索引存储器，usage_event_compaction - 使用事件压缩配置
        # 返回值：HybridSessionStore 实例
        def initialize(data_dir:, index:, usage_event_compaction: {})
          @delegate = ::DeepForge::Adapters::FileStore::FileSessionStore.new(
            data_dir: data_dir,
            usage_event_compaction: usage_event_compaction
          )
          @index = index
        end

        # 方法功能：追加运行时事件到指定线程
        # 写入文件后更新 SQLite 索引中的事件序列号
        # 参数：thread_id - 线程ID，event - 事件哈希
        # 返回值：无
        def append_event(thread_id, event)
          @delegate.append_event(thread_id, event)
          @index.note_event_seq(thread_id, event[:seq])
        end

        # 方法功能：追加对话轮次项到指定线程
        # 参数：thread_id - 线程ID，item - 对话轮次项哈希
        # 返回值：无
        def append_item(thread_id, item)
          @delegate.append_item(thread_id, item)
        end

        # 方法功能：重写指定线程的所有对话轮次项
        # 参数：thread_id - 线程ID，items - 对话轮次项数组
        # 返回值：无
        def rewrite_items(thread_id, items)
          @delegate.rewrite_items(thread_id, items)
        end

        # 方法功能：更新指定线程中的对话轮次项
        # 参数：thread_id - 线程ID，item_id - 项ID，patch - 要应用的部分字段
        # 返回值：更新后的项哈希，未找到则返回 nil
        def update_item(thread_id, item_id, patch)
          @delegate.update_item(thread_id, item_id, patch)
        end

        # 方法功能：加载指定线程自某个序列号之后的所有事件
        # 参数：thread_id - 线程ID，since_seq - 起始序列号
        # 返回值：事件数组，按序列号升序排列
        def load_events_since(thread_id, since_seq)
          @delegate.load_events_since(thread_id, since_seq)
        end

        # 方法功能：加载指定线程的所有对话轮次项
        # 参数：thread_id - 线程ID
        # 返回值：对话轮次项数组，按ID去重并保留最新版本
        def load_items(thread_id)
          @delegate.load_items(thread_id)
        end

        # 方法功能：加载指定线程的会话记录
        # 参数：thread_id - 线程ID
        # 返回值：会话记录哈希，未找到则返回 nil
        def load_session(thread_id)
          @delegate.load_session(thread_id)
        end

        # 方法功能：插入或更新会话记录
        # 参数：session - 会话记录哈希
        # 返回值：无
        def upsert_session(session)
          @delegate.upsert_session(session)
        end

        # 方法功能：获取指定线程中事件的最大序列号
        # 参数：thread_id - 线程ID
        # 返回值：最大序列号整数
        def highest_seq(thread_id)
          @delegate.highest_seq(thread_id)
        end

        # 方法功能：重置内存状态
        # 返回值：无
        def reset_memory
          @delegate.reset_memory
        end
      end
    end
  end
end
