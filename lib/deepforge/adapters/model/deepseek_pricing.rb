# frozen_string_literal: true

# 文件用途：DeepSeek 模型定价估算模块
# 使用方法：根据模型名称和 token 使用量估算 API 调用成本。支持 USD 和 CNY 双币种计算，
#           包含缓存命中和未命中两种输入 token 价格。提供 flash 和 pro 两个价格档位。

module DeepForge
  module Adapters
    module Model
      # DeepSeek 定价估算模块，用于计算 API 调用成本。
      module DeepseekPricing
        # 每百万 token 数量常量
        TOKENS_PER_MILLION = 1_000_000

        # 官方 DeepSeek API 每百万 token 的价格（截至 2026-06-02）
        # deepseek-chat/deepseek-reasoner 是 v4-flash 模式的别名
        PRICES = {
          flash: {
            usd: { input_cache_hit: 0.0028, input_cache_miss: 0.14, output: 0.28 },
            cny: { input_cache_hit: 0.02, input_cache_miss: 1, output: 2 }
          },
          pro: {
            usd: { input_cache_hit: 0.003625, input_cache_miss: 0.435, output: 0.87 },
            cny: { input_cache_hit: 0.025, input_cache_miss: 3, output: 6 }
          }
        }.freeze

        module_function

        # 根据模型名称确定其定价档位
        # 参数：model - 模型名称字符串
        # 返回值：Symbol（:flash 或 :pro）或 nil（未知模型）
        def pricing_tier_for_model(model)
          normalized = model.strip.downcase
          return nil if normalized.empty?

          return :pro if normalized == 'deepseek-v4-pro' || normalized.end_with?('/deepseek-v4-pro')

          flash_models = %w[deepseek-v4-flash deepseek-chat deepseek-reasoner]
          return :flash if flash_models.include?(normalized) ||
                           flash_models.any? { |m| normalized.end_with?("/#{m}") }

          nil
        end

        # 根据价格和 token 数量计算成本
        # 参数：price - 价格哈希（含 input_cache_hit, input_cache_miss, output 键），
        #        cache_hit_tokens - 缓存命中 token 数，cache_miss_tokens - 缓存未命中 token 数，
        #        output_tokens - 输出 token 数
        # 返回值：Float，计算出的成本（美元或人民币）
        def compute_cost(price, cache_hit_tokens, cache_miss_tokens, output_tokens)
          ((cache_hit_tokens.to_f / TOKENS_PER_MILLION) * price[:input_cache_hit]) +
            ((cache_miss_tokens.to_f / TOKENS_PER_MILLION) * price[:input_cache_miss]) +
            ((output_tokens.to_f / TOKENS_PER_MILLION) * price[:output])
        end

        # 估算 DeepSeek API 调用的总成本（双币种）
        # 参数：model - 模型名称，cache_hit_tokens - 缓存命中数，cache_miss_tokens - 缓存未命中数，
        #        output_tokens - 输出 token 数
        # 返回值：Hash（含 cost_usd 和 cost_cny 键）或 nil（未知模型）
        def estimate_deepseek_cost(model:, cache_hit_tokens:, cache_miss_tokens:, output_tokens:)
          tier = pricing_tier_for_model(model)
          return nil unless tier

          prices = PRICES[tier]
          {
            cost_usd: compute_cost(prices[:usd], cache_hit_tokens, cache_miss_tokens, output_tokens),
            cost_cny: compute_cost(prices[:cny], cache_hit_tokens, cache_miss_tokens, output_tokens)
          }
        end

        # 估算 DeepSeek API 输入 token 的成本（假设全部为缓存未命中）
        # 参数：model - 模型名称，input_tokens - 输入 token 数
        # 返回值：Hash（含 cost_usd 和 cost_cny 键）或 nil（未知模型）
        def estimate_deepseek_input_token_cost(model:, input_tokens:)
          estimate_deepseek_cost(
            model: model,
            cache_hit_tokens: 0,
            cache_miss_tokens: input_tokens,
            output_tokens: 0
          )
        end

        # 估算缓存命中带来的节省金额
        # 参数：model - 模型名称，cache_hit_tokens - 缓存命中 token 数
        # 返回值：Hash（含 cost_usd 和 cost_cny 键）或 nil（未知模型）
        def estimate_deepseek_cache_savings(model:, cache_hit_tokens:)
          tier = pricing_tier_for_model(model)
          return nil unless tier

          prices = PRICES[tier]
          {
            cost_usd: (cache_hit_tokens.to_f / TOKENS_PER_MILLION) *
              [0, prices[:usd][:input_cache_miss] - prices[:usd][:input_cache_hit]].max,
            cost_cny: (cache_hit_tokens.to_f / TOKENS_PER_MILLION) *
              [0, prices[:cny][:input_cache_miss] - prices[:cny][:input_cache_hit]].max
          }
        end
      end
    end
  end
end
