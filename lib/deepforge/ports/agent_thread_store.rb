# frozen_string_literal: true

# 文件用途：线程存储端口，提供持久化线程数据存储功能
# 使用方法：继承此类并实现list、get、upsert、delete方法，使用JSONL日志和可查询索引

module DeepForge
  module Ports
    # @abstract Subclass and implement {#list}, {#get}, {#upsert}, {#delete}
    # Port for persistent thread storage. Implementations use a JSONL
    # messages log plus a queryable index; the in-memory implementation is
    # used by tests.

    # 类功能：线程存储端口基类，定义线程数据CRUD接口
    class AgentThreadStore
      # 方法功能：列出线程摘要
      # 参数：options - 可选过滤选项哈希
      # 选项：limit - 最大结果数，search - 搜索查询，include_archived - 包含已归档线程
      #       archived_only - 仅已归档线程，include_side - 包含侧线程
      # 返回值：线程摘要数组
      # 使用方法：传入过滤选项，返回匹配的线程摘要列表
      # @param options [Hash] optional filtering options
      # @option options [Integer] :limit maximum number of results
      # @option options [String] :search search query
      # @option options [Boolean] :include_archived include archived threads
      # @option options [Boolean] :archived_only only archived threads
      # @option options [Boolean] :include_side include side threads
      # @return [Array<Contracts::ThreadSummary>]
      def list(options = {})
        raise NotImplementedError
      end

      # 方法功能：获取指定线程记录
      # 参数：thread_id - 线程ID
      # 返回值：线程记录对象或nil
      # 使用方法：传入线程ID，返回对应的线程记录
      # @param thread_id [String]
      # @return [Contracts::ThreadRecord, nil]
      def get(thread_id)
        raise NotImplementedError
      end

      # 方法功能：插入或更新线程记录
      # 参数：thread - 线程记录对象
      # 返回值：保存后的线程记录对象
      # 使用方法：传入线程记录对象，创建或更新存储
      # @param thread [Contracts::ThreadRecord]
      # @return [Contracts::ThreadRecord]
      def upsert(thread)
        raise NotImplementedError
      end

      # 方法功能：删除指定线程
      # 参数：thread_id - 线程ID
      # 返回值：布尔值表示删除是否成功
      # 使用方法：传入线程ID，删除对应的线程记录
      # @param thread_id [String]
      # @return [Boolean]
      def delete(thread_id)
        raise NotImplementedError
      end
    end
  end
end
