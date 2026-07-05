# frozen_string_literal: true

# 文件用途：缓存遥测数据收集模块
# 使用方法：累加模型响应、压缩摘要和显式变更中的缓存计数器，
#           为 GUI 的"缓存命中率"徽章提供数据源。

require_relative '../contracts/usage'

module DeepForge
  module Telemetry
    # 缓存遥测累加器类，按线程追踪缓存命中、未命中、写入和失效统计
    class CacheTelemetry
      def initialize
        @hits = Hash.new(0)
        @misses = Hash.new(0)
        @writes = Hash.new(0)
        @invalidations = Hash.new(0)
      end

      # 方法功能：记录缓存命中
      # 参数：thread_id - 线程 ID
      #       tokens - 命中的 token 数量
      # 返回值：void
      def record_hit(thread_id, tokens)
        @hits[thread_id] += tokens
      end

      # 方法功能：记录缓存未命中
      # 参数：thread_id - 线程 ID
      #       tokens - 未命中的 token 数量
      # 返回值：void
      def record_miss(thread_id, tokens)
        @misses[thread_id] += tokens
      end

      # 方法功能：记录缓存写入
      # 参数：thread_id - 线程 ID
      #       tokens - 写入的 token 数量
      # 返回值：void
      def record_write(thread_id, tokens)
        @writes[thread_id] += tokens
      end

      # 方法功能：记录缓存失效
      # 参数：thread_id - 线程 ID
      # 返回值：void
      def record_invalidation(thread_id)
        @invalidations[thread_id] += 1
      end

      # 方法功能：从使用量快照中提取缓存指标
      # 参数：thread_id - 线程 ID
      #       usage - 使用量快照对象
      # 返回值：void
      def ingest(thread_id, usage)
        record_hit(thread_id, usage.cache_hit_tokens) if usage.cache_hit_tokens
        record_miss(thread_id, usage.cache_miss_tokens) if usage.cache_miss_tokens
        return unless usage.cached_tokens && usage.cached_tokens > (usage.cache_hit_tokens || 0)

        record_write(thread_id, usage.cached_tokens - (usage.cache_hit_tokens || 0))
      end

      # 方法功能：获取指定线程的缓存遥测快照
      # 参数：thread_id - 线程 ID
      # 返回值：Hash - 包含 hits、misses、writes、invalidations、hit_rate 的哈希
      def snapshot(thread_id)
        hits = @hits[thread_id] || 0
        misses = @misses[thread_id] || 0
        total = hits + misses
        {
          hits: hits,
          misses: misses,
          writes: @writes[thread_id] || 0,
          invalidations: @invalidations[thread_id] || 0,
          hit_rate: total.zero? ? nil : hits.to_f / total
        }
      end

      # 方法功能：重置缓存遥测数据
      # 参数：thread_id - 可选的线程 ID，不传则重置所有数据
      # 返回值：void
      def reset(thread_id = nil)
        if thread_id.nil?
          @hits.clear
          @misses.clear
          @writes.clear
          @invalidations.clear
          return
        end
        @hits.delete(thread_id)
        @misses.delete(thread_id)
        @writes.delete(thread_id)
        @invalidations.delete(thread_id)
      end
    end
  end
end
