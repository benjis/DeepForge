# frozen_string_literal: true

# 文件用途：模型请求 token 估算器，估算请求的输入 token 数量
# 使用方法：通过 ModelRequestEstimator.estimate_input_tokens(request) 调用

require 'json'

# 模块功能：模型请求 token 估算
# 估算模型请求各部分的 token 数量，包括系统提示、历史、工具等
module DeepForge
  module Loop
    module ModelRequestEstimator
      module_function

      # 每 token 的近似字符数
      CHARS_PER_TOKEN = 4

      ContextEstimator.new(CHARS_PER_TOKEN)

      # 估算模型请求的输入 token 总数
      # @param request [Hash] 模型请求
      # @return [Integer] 估算的输入 token 数
      def estimate_input_tokens(request)
        tokens = 0
        tokens += estimate_text(request[:system_prompt])
        tokens += estimate_text(request[:mode_instruction])
        tokens += estimate_text((request[:context_instructions] || []).join("\n"))
        tokens += estimate_items(request[:prefix] || [])
        tokens += estimate_items(request[:history] || [])
        tokens += estimate_tools(request[:tools] || [])
        tokens += estimate_text_fallbacks(request[:attachment_text_fallbacks])
        tokens += estimate_text(request[:required_tool_name])
        tokens += estimate_text(request[:reasoning_effort])
        [0, tokens].max
      end

      # 估算条目列表的 token 数量
      # @param items [Array<Hash>] 待估算的条目
      # @return [Integer] 估算的 token 数
      def estimate_items(items)
        items.empty? ? 0 : estimator.estimate_items(items)
      end

      # 估算工具定义的 token 数量
      # @param tools [Array<Hash>] 待估算的工具
      # @return [Integer] 估算的 token 数
      def estimate_tools(tools)
        tools.sum do |tool|
          estimate_text([
            tool[:name],
            tool[:description],
            JSON.generate(tool[:input_schema] || tool['inputSchema'] || {})
          ].join("\n"))
        end
      end

      # 估算文本回退内容的 token 数量
      # @param fallbacks [Array<Hash>, nil] 文本回退内容
      # @return [Integer] 估算的 token 数
      def estimate_text_fallbacks(fallbacks)
        return 0 unless fallbacks&.any?

        fallbacks.sum do |attachment|
          estimate_text([
            attachment[:name],
            attachment[:mime_type],
            attachment[:byte_size].to_s,
            attachment[:data_base64]
          ].join("\n"))
        end
      end

      # 估算文本的 token 数量
      # @param text [String, nil] 待估算的文本
      # @return [Integer] 估算的 token 数
      def estimate_text(text)
        return 0 if text.nil? || text.strip.empty?

        [1, (text.length / CHARS_PER_TOKEN.to_f).ceil].max
      end
    end
  end
end
