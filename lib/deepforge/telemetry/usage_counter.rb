# frozen_string_literal: true

# 文件用途：按线程的使用量计数器模块
# 使用方法：累加模型响应中的 token、缓存、回合和成本计数器，
#           缺失值自动回退为零/空，不会抛出异常。

require_relative '../contracts/usage'

module DeepForge
  module Telemetry
    # 按线程的使用量计数器类，累加 token、缓存、回合和成本统计
    class UsageCounter
      def initialize
        @per_thread = {}
      end

      # 方法功能：重置使用量计数器
      # 参数：thread_id - 可选的线程 ID，不传则重置所有数据
      # 返回值：void
      def reset(thread_id = nil)
        if thread_id.nil?
          @per_thread.clear
          return
        end
        @per_thread.delete(thread_id)
      end

      # 方法功能：初始化指定线程的使用量快照
      # 参数：thread_id - 线程 ID
      #       snapshot - 使用量快照对象
      # 返回值：Contracts::UsageSnapshot - 标准化后的快照
      def seed(thread_id, snapshot)
        next_snapshot = normalize_usage_snapshot(snapshot)
        @per_thread[thread_id] = next_snapshot
        next_snapshot
      end

      # 方法功能：将使用量快照累加到按线程的计数器中
      # 参数：thread_id - 线程 ID
      #       snapshot - 使用量快照对象
      # 返回值：Contracts::UsageSnapshot - 累加后的快照
      def record(thread_id, snapshot)
        current = @per_thread[thread_id] || Contracts.empty_usage_snapshot

        prompt_tokens = current.prompt_tokens + snapshot.prompt_tokens
        completion_tokens = current.completion_tokens + snapshot.completion_tokens
        total_tokens = prompt_tokens + completion_tokens
        cached_tokens = (current.cached_tokens || 0) + (snapshot.cached_tokens || 0)
        cache_hit_tokens = (current.cache_hit_tokens || 0) + (snapshot.cache_hit_tokens || 0)
        cache_miss_tokens = (current.cache_miss_tokens || 0) + (snapshot.cache_miss_tokens || 0)
        cache_total = cache_hit_tokens + cache_miss_tokens
        cache_hit_rate = cache_total.zero? ? nil : cache_hit_tokens.to_f / cache_total
        turns = current.turns + (snapshot.turns.positive? ? snapshot.turns : 1)

        cost_usd = merge_optional_cost(current.cost_usd, snapshot.cost_usd)
        cost_cny = merge_optional_cost(current.cost_cny, snapshot.cost_cny)
        cache_savings_usd = merge_optional_cost(current.cache_savings_usd, snapshot.cache_savings_usd)
        cache_savings_cny = merge_optional_cost(current.cache_savings_cny, snapshot.cache_savings_cny)
        token_economy_savings_tokens = (current.token_economy_savings_tokens || 0) + (snapshot.token_economy_savings_tokens || 0)
        token_economy_savings_usd = merge_optional_cost(current.token_economy_savings_usd,
                                                        snapshot.token_economy_savings_usd)
        token_economy_savings_cny = merge_optional_cost(current.token_economy_savings_cny,
                                                        snapshot.token_economy_savings_cny)

        next_snapshot = Contracts::UsageSnapshot.new(
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: total_tokens,
          cached_tokens: cached_tokens,
          cache_hit_tokens: cache_hit_tokens,
          cache_miss_tokens: cache_miss_tokens,
          cache_hit_rate: cache_hit_rate,
          turns: turns,
          cost_usd: cost_usd,
          cost_cny: cost_cny,
          cache_savings_usd: cache_savings_usd,
          cache_savings_cny: cache_savings_cny,
          token_economy_savings_tokens: token_economy_savings_tokens,
          token_economy_savings_usd: token_economy_savings_usd,
          token_economy_savings_cny: token_economy_savings_cny,
          has_error: snapshot.has_error
        )
        @per_thread[thread_id] = next_snapshot
        next_snapshot
      end

      # 方法功能：记录 token 经济节省量
      # 参数：thread_id - 线程 ID
      #       savings - 包含节省量信息的哈希
      # 返回值：Contracts::UsageSnapshot - 更新后的快照
      def record_token_economy_savings(thread_id, savings)
        current = @per_thread[thread_id] || Contracts.empty_usage_snapshot

        next_snapshot = Contracts::UsageSnapshot.new(
          prompt_tokens: current.prompt_tokens,
          completion_tokens: current.completion_tokens,
          total_tokens: current.total_tokens,
          cached_tokens: current.cached_tokens,
          cache_hit_tokens: current.cache_hit_tokens,
          cache_miss_tokens: current.cache_miss_tokens,
          cache_hit_rate: current.cache_hit_rate,
          turns: current.turns,
          cost_usd: current.cost_usd,
          cost_cny: current.cost_cny,
          cache_savings_usd: current.cache_savings_usd,
          cache_savings_cny: current.cache_savings_cny,
          token_economy_savings_tokens: (current.token_economy_savings_tokens || 0) + (savings[:token_economy_savings_tokens] || 0),
          token_economy_savings_usd: merge_optional_cost(current.token_economy_savings_usd,
                                                         savings[:token_economy_savings_usd]),
          token_economy_savings_cny: merge_optional_cost(current.token_economy_savings_cny,
                                                         savings[:token_economy_savings_cny]),
          has_error: current.has_error
        )
        @per_thread[thread_id] = next_snapshot
        next_snapshot
      end

      # 方法功能：获取所有线程的总使用量
      # 返回值：Contracts::UsageSnapshot - 所有线程的汇总快照
      def total
        @per_thread.values.reduce(Contracts.empty_usage_snapshot) do |acc, snapshot|
          merge_usage(acc, snapshot)
        end
      end

      # 方法功能：获取指定线程的使用量快照
      # 参数：thread_id - 线程 ID
      # 返回值：Contracts::UsageSnapshot - 指定线程的使用量快照
      def for_thread(thread_id)
        @per_thread[thread_id] || Contracts.empty_usage_snapshot
      end

      private

      # 方法功能：标准化使用量快照，确保所有值为非负数
      # 参数：snapshot - 原始使用量快照
      # 返回值：Contracts::UsageSnapshot - 标准化后的快照
      def normalize_usage_snapshot(snapshot)
        prompt_tokens = [0, snapshot.prompt_tokens.to_i].max
        completion_tokens = [0, snapshot.completion_tokens.to_i].max
        total_tokens = [0, (snapshot.total_tokens || (prompt_tokens + completion_tokens)).to_i].max
        cached_tokens = snapshot.cached_tokens ? [0, snapshot.cached_tokens.to_i].max : nil
        cache_hit_tokens = snapshot.cache_hit_tokens ? [0, snapshot.cache_hit_tokens.to_i].max : nil
        cache_miss_tokens = snapshot.cache_miss_tokens ? [0, snapshot.cache_miss_tokens.to_i].max : nil
        cache_total = (cache_hit_tokens || 0) + (cache_miss_tokens || 0)

        Contracts::UsageSnapshot.new(
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: total_tokens,
          cached_tokens: cached_tokens,
          cache_hit_tokens: cache_hit_tokens,
          cache_miss_tokens: cache_miss_tokens,
          cache_hit_rate: cache_hit_tokens && cache_total.positive? ? cache_hit_tokens.to_f / cache_total : nil,
          turns: [0, snapshot.turns.to_i].max,
          cost_usd: snapshot.cost_usd ? [0, snapshot.cost_usd].max : nil,
          cost_cny: snapshot.cost_cny ? [0, snapshot.cost_cny].max : nil,
          cache_savings_usd: snapshot.cache_savings_usd ? [0, snapshot.cache_savings_usd].max : nil,
          cache_savings_cny: snapshot.cache_savings_cny ? [0, snapshot.cache_savings_cny].max : nil,
          token_economy_savings_tokens: if snapshot.token_economy_savings_tokens
                                          [0,
                                           snapshot.token_economy_savings_tokens.to_i].max
                                        end,
          token_economy_savings_usd: if snapshot.token_economy_savings_usd
                                       [0,
                                        snapshot.token_economy_savings_usd].max
                                     end,
          token_economy_savings_cny: if snapshot.token_economy_savings_cny
                                       [0,
                                        snapshot.token_economy_savings_cny].max
                                     end,
          has_error: snapshot.has_error
        )
      end

      # 方法功能：合并两个使用量快照
      # 参数：into - 目标快照
      #       delta - 增量快照
      # 返回值：Contracts::UsageSnapshot - 合并后的快照
      def merge_usage(into, delta)
        prompt_tokens = into.prompt_tokens + delta.prompt_tokens
        completion_tokens = into.completion_tokens + delta.completion_tokens
        total_tokens = prompt_tokens + completion_tokens
        cached_tokens = (into.cached_tokens || 0) + (delta.cached_tokens || 0)
        cache_hit_tokens = (into.cache_hit_tokens || 0) + (delta.cache_hit_tokens || 0)
        cache_miss_tokens = (into.cache_miss_tokens || 0) + (delta.cache_miss_tokens || 0)
        cache_total = cache_hit_tokens + cache_miss_tokens
        cache_hit_rate = cache_total.zero? ? nil : cache_hit_tokens.to_f / cache_total
        turns = into.turns + delta.turns

        Contracts::UsageSnapshot.new(
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: total_tokens,
          cached_tokens: cached_tokens,
          cache_hit_tokens: cache_hit_tokens,
          cache_miss_tokens: cache_miss_tokens,
          cache_hit_rate: cache_hit_rate,
          turns: turns,
          cost_usd: merge_optional_cost(into.cost_usd, delta.cost_usd),
          cost_cny: merge_optional_cost(into.cost_cny, delta.cost_cny),
          cache_savings_usd: merge_optional_cost(into.cache_savings_usd, delta.cache_savings_usd),
          cache_savings_cny: merge_optional_cost(into.cache_savings_cny, delta.cache_savings_cny),
          token_economy_savings_tokens: (into.token_economy_savings_tokens || 0) + (delta.token_economy_savings_tokens || 0),
          token_economy_savings_usd: merge_optional_cost(into.token_economy_savings_usd,
                                                         delta.token_economy_savings_usd),
          token_economy_savings_cny: merge_optional_cost(into.token_economy_savings_cny,
                                                         delta.token_economy_savings_cny),
          has_error: into.has_error || delta.has_error
        )
      end

      # 方法功能：合并可选的成本值
      # 参数：a - 第一个成本值（可为 nil）
      #       b - 第二个成本值（可为 nil）
      # 返回值：Float 或 nil - 合并后的成本值
      def merge_optional_cost(a, b)
        return nil if a.nil? && b.nil?

        (a || 0) + (b || 0)
      end
    end
  end
end
