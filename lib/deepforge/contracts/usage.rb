# frozen_string_literal: true

# 文件用途：定义用量统计相关的请求、响应和数据结构
# 使用方法：用于追踪 token 使用量、缓存命中率和成本统计

module DeepForge
  module Contracts
    # 用量快照：每次模型响应返回的 token、缓存和成本计数器
    UsageSnapshot = Struct.new(
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :cached_tokens,
      :cache_hit_tokens,
      :cache_miss_tokens,
      :cache_hit_rate,
      :turns,
      :cost_usd,
      :cost_cny,
      :cache_savings_usd,
      :cache_savings_cny,
      :token_economy_savings_tokens,
      :token_economy_savings_usd,
      :token_economy_savings_cny,
      :has_error,
      keyword_init: true
    )

    # 每日用量计数器：包含输入、输出、推理和缓存 token 的统计
    DailyUsageCounters = Struct.new(
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cached_tokens,
      :cache_miss_tokens,
      :total_tokens,
      :cost_usd,
      :cost_cny,
      :cache_savings_usd,
      :cache_savings_cny,
      :token_economy_savings_tokens,
      :token_economy_savings_usd,
      :token_economy_savings_cny,
      :turns,
      :thread_count,
      :cache_hit_rate,
      keyword_init: true
    )

    # 每日用量桶：按日期聚合的用量统计数据
    DailyUsageBucket = Struct.new(
      :date,
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cached_tokens,
      :cache_miss_tokens,
      :total_tokens,
      :cost_usd,
      :cost_cny,
      :cache_savings_usd,
      :cache_savings_cny,
      :token_economy_savings_tokens,
      :token_economy_savings_usd,
      :token_economy_savings_cny,
      :turns,
      :thread_count,
      :cache_hit_rate,
      keyword_init: true
    )

    # 每日用量汇总：所有日期的汇总统计数据
    DailyUsageTotals = Struct.new(
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cached_tokens,
      :cache_miss_tokens,
      :total_tokens,
      :cost_usd,
      :cost_cny,
      :cache_savings_usd,
      :cache_savings_cny,
      :token_economy_savings_tokens,
      :token_economy_savings_usd,
      :token_economy_savings_cny,
      :turns,
      :thread_count,
      :cache_hit_rate,
      :days,
      :active_days,
      keyword_init: true
    )

    # 每日用量响应：返回按日期分组的用量数据
    DailyUsageResponse = Struct.new(
      :group_by,
      :from,
      :to,
      :timezone,
      :buckets,
      :totals,
      keyword_init: true
    )

    # 线程用量桶：按线程聚合的用量统计数据
    ThreadUsageBucket = Struct.new(
      :thread_id,
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cached_tokens,
      :cache_miss_tokens,
      :total_tokens,
      :cost_usd,
      :cost_cny,
      :cache_savings_usd,
      :cache_savings_cny,
      :token_economy_savings_tokens,
      :token_economy_savings_usd,
      :token_economy_savings_cny,
      :turns,
      :cache_hit_rate,
      keyword_init: true
    )

    # 线程用量汇总：所有线程的汇总统计数据
    ThreadUsageTotals = Struct.new(
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cached_tokens,
      :cache_miss_tokens,
      :total_tokens,
      :cost_usd,
      :cost_cny,
      :cache_savings_usd,
      :cache_savings_cny,
      :token_economy_savings_tokens,
      :token_economy_savings_usd,
      :token_economy_savings_cny,
      :turns,
      :thread_count,
      :cache_hit_rate,
      keyword_init: true
    )

    # 线程用量响应：返回按线程分组的用量数据
    ThreadUsageResponse = Struct.new(
      :group_by,
      :buckets,
      :totals,
      keyword_init: true
    )

    # 模型用量桶：按模型聚合的用量统计数据
    ModelUsageBucket = Struct.new(
      :model,
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cached_tokens,
      :cache_miss_tokens,
      :total_tokens,
      :cost_usd,
      :cost_cny,
      :cache_savings_usd,
      :cache_savings_cny,
      :token_economy_savings_tokens,
      :token_economy_savings_usd,
      :token_economy_savings_cny,
      :turns,
      :thread_count,
      :cache_hit_rate,
      keyword_init: true
    )

    # 模型每日用量桶：按模型和日期聚合的用量数据（类型别名）
    ModelUsageDayBucket = DailyUsageBucket

    # 模型用量响应：返回按模型和日期分组的用量数据
    ModelUsageResponse = Struct.new(
      :group_by,
      :from,
      :to,
      :timezone,
      :buckets,
      :days,
      :totals,
      keyword_init: true
    )

    # 创建空的用量快照：所有计数器为零
    def self.empty_usage_snapshot
      UsageSnapshot.new(
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0,
        cached_tokens: 0,
        cache_hit_tokens: 0,
        cache_miss_tokens: 0,
        cache_hit_rate: nil,
        turns: 0,
        cache_savings_usd: 0,
        cache_savings_cny: 0,
        token_economy_savings_tokens: 0,
        token_economy_savings_usd: 0,
        token_economy_savings_cny: 0
      )
    end
  end
end
