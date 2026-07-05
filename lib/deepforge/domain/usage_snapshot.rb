# frozen_string_literal: true

# 文件用途：定义用量计算的领域模型和工具方法
# 使用方法：用于创建零用量快照和合并用量数据

module DeepForge
  module Domain
    # 用量实体类型：引用用量快照契约类型
    UsageSnapshotEntity = Contracts::UsageSnapshot

    # 创建零用量快照：所有计数器为零的初始状态
    def self.zero_usage
      Contracts.empty_usage_snapshot
    end

    # 合并用量数据：将增量用量加到现有用量上
    # 参数：into - 现有用量快照；delta - 新增用量快照
    # 返回值：合并后的新用量快照
    def self.add_usage(into, delta)
      prompt_tokens = into.prompt_tokens + delta.prompt_tokens
      completion_tokens = into.completion_tokens + delta.completion_tokens
      total_tokens = prompt_tokens + completion_tokens
      cached_tokens = (into.cached_tokens || 0) + (delta.cached_tokens || 0)
      cache_hit_tokens = (into.cache_hit_tokens || 0) + (delta.cache_hit_tokens || 0)
      cache_miss_tokens = (into.cache_miss_tokens || 0) + (delta.cache_miss_tokens || 0)
      cache_total = cache_hit_tokens + cache_miss_tokens
      cache_hit_rate = cache_total.zero? ? nil : cache_hit_tokens.to_f / cache_total
      turns = into.turns + delta.turns

      cost_usd = if into.cost_usd.nil? && delta.cost_usd.nil?
                   nil
                 else
                   (into.cost_usd || 0) + (delta.cost_usd || 0)
                 end

      cost_cny = if into.cost_cny.nil? && delta.cost_cny.nil?
                   nil
                 else
                   (into.cost_cny || 0) + (delta.cost_cny || 0)
                 end

      cache_savings_usd = if into.cache_savings_usd.nil? && delta.cache_savings_usd.nil?
                            nil
                          else
                            (into.cache_savings_usd || 0) + (delta.cache_savings_usd || 0)
                          end

      cache_savings_cny = if into.cache_savings_cny.nil? && delta.cache_savings_cny.nil?
                            nil
                          else
                            (into.cache_savings_cny || 0) + (delta.cache_savings_cny || 0)
                          end

      token_economy_savings_tokens = (into.token_economy_savings_tokens || 0) + (delta.token_economy_savings_tokens || 0)

      token_economy_savings_usd = if into.token_economy_savings_usd.nil? && delta.token_economy_savings_usd.nil?
                                    nil
                                  else
                                    (into.token_economy_savings_usd || 0) + (delta.token_economy_savings_usd || 0)
                                  end

      token_economy_savings_cny = if into.token_economy_savings_cny.nil? && delta.token_economy_savings_cny.nil?
                                    nil
                                  else
                                    (into.token_economy_savings_cny || 0) + (delta.token_economy_savings_cny || 0)
                                  end

      Contracts::UsageSnapshot.new(
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
        token_economy_savings_cny: token_economy_savings_cny
      )
    end
  end
end
