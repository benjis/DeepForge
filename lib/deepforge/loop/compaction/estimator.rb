# frozen_string_literal: true

# 文件用途：轻量级 token 估算器，用于触发压缩阈值判断
# 使用方法：通过 ContextEstimator.new(chars_per_token) 创建实例
# 估算器故意设计得简单：目标是在合理阈值触发压缩，而非精确建模提供商的分词器

require 'json'

# 类功能：轻量级 token 估算器
# 优先使用报告的用量数据，否则按每约 4 个字符一个 token 近似估算
module DeepForge
  module Loop
    class ContextEstimator
      # 初始化估算器
      # @param chars_per_token [Float] 每 token 的近似字符数
      def initialize(chars_per_token = 4)
        @chars_per_token = chars_per_token
      end

      # 估算单个轮次条目的 token 数量
      # @param item [Hash] 轮次条目
      # @return [Integer] 估算的 token 数
      def estimate_item(item)
        text = collect_text(item)
        [1, (text.length / @chars_per_token).ceil].max
      end

      # 估算多个轮次条目的总 token 数量
      # @param items [Array<Hash>] 轮次条目列表
      # @return [Integer] 总估算 token 数
      def estimate_items(items)
        items.sum { |item| estimate_item(item) }
      end

      private

      # 从条目中收集用于估算的文本内容
      # @param item [Hash] 轮次条目
      # @return [String] 用于估算的文本
      def collect_text(item)
        case item[:kind]
        when 'user_message', 'assistant_text', 'assistant_reasoning'
          item[:text]
        when 'tool_call'
          "#{item[:tool_name]} #{JSON.generate(item[:arguments])}"
        when 'tool_result'
          item[:output].is_a?(String) ? item[:output] : JSON.generate(item[:output])
        when 'approval'
          "#{item[:tool_name]} #{item[:summary]}"
        when 'user_input'
          item[:prompt]
        when 'compaction'
          item[:summary]
        when 'review'
          "#{item[:title]} #{item[:review_text] || ''} #{JSON.generate(item[:output]) if item[:output]}"
        when 'error'
          item[:message]
        else
          ''
        end
      end
    end
  end
end
