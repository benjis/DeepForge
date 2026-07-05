# frozen_string_literal: true

# 文件用途：工具速率限制检测
# 使用方法：通过 ToolRateLimit 模块检测和处理工具执行的速率限制响应

module DeepForge
  module Adapters
    module Tool
      # 速率限制解析结果结构体
      ParsedRateLimit = Struct.new(:rate_limited, :message, :retry_after_seconds, keyword_init: true)

      # 速率限制检测正则表达式
      RATE_LIMIT_RE = /\b(rate[-\s]?limit(?:ed|ing)?|too many requests|quota exceeded|request limit|(?:http|status)\s*:?\s*429)\b/i
      # 重试时间检测正则表达式
      RETRY_AFTER_RE = /\b(?:retry[-\s]?after|try again in|wait)\s*:?\s*(\d+(?:\.\d+)?)\s*(ms|milliseconds?|s|sec|seconds?|m|min|minutes?)?\b/i

      # 模块功能：检测和处理工具执行中的速率限制
      module ToolRateLimit
        # 方法功能：解析工具结果中的速率限制信息
        # 参数：output - 工具输出对象
        # 返回值：ParsedRateLimit 结构体或 nil
        def self.parse_rate_limited_tool_result(output)
          text = collect_text(output).join("\n").strip
          return nil if text.empty? || !RATE_LIMIT_RE.match?(text)

          retry_after = parse_retry_after_seconds(text)
          ParsedRateLimit.new(
            rate_limited: true,
            message: compact_rate_limit_message(text),
            retry_after_seconds: retry_after
          )
        end

        # Normalize rate-limited tool output.
        # @param output [Object]
        # @return [Hash] with :output, :is_error, :rate_limited
        # 方法功能：规范化速率限制的工具输出
        # 参数：output - 工具输出对象
        # 返回值：包含 :output、:is_error 和 :rate_limited 的哈希
        def self.normalize_rate_limited_tool_output(output)
          parsed = parse_rate_limited_tool_result(output)
          return { output: output, is_error: false, rate_limited: false } unless parsed

          normalized = {
            code: 'rate_limited',
            rate_limited: true,
            error: parsed.message,
            original: output
          }
          normalized[:retry_after_seconds] = parsed.retry_after_seconds if parsed.retry_after_seconds

          {
            output: normalized,
            is_error: true,
            rate_limited: true
          }
        end

        class << self
          private

          # Collect text from nested output.
          # @param value [Object]
          # @param depth [Integer]
          # @return [Array<String>]
          # 方法功能：从嵌套输出中收集文本
          # 参数：value - 值对象，depth - 当前深度
          # 返回值：字符串数组
          def collect_text(value, depth = 0)
            return [] if depth > 4 || value.nil?

            case value
            when String
              [value]
            when Numeric, TrueClass, FalseClass
              [value.to_s]
            when Array
              value.flat_map { |entry| collect_text(entry, depth + 1) }
            when Hash
              out = []
              value.each do |key, child|
                if child.is_a?(String) || child.is_a?(Numeric) || child.is_a?(TrueClass) || child.is_a?(FalseClass)
                  out << "#{key}: #{child}"
                else
                  out.concat(collect_text(child, depth + 1))
                end
              end
              out
            else
              []
            end
          end

          # Parse retry-after seconds from text.
          # @param text [String]
          # @return [Float, nil]
          # 方法功能：从文本中解析重试等待秒数
          # 参数：text - 文本字符串
          # 返回值：秒数或 nil
          def parse_retry_after_seconds(text)
            match = RETRY_AFTER_RE.match(text)
            return nil unless match

            value = match[1].to_f
            return nil unless value.finite? && value >= 0

            unit = (match[2] || 's').downcase
            if unit.start_with?('ms') || unit.start_with?('millisecond')
              (value / 1000.0).ceil.to_f
            elsif unit.start_with?('m') && !unit.start_with?('ms')
              (value * 60).ceil.to_f
            else
              value.ceil.to_f
            end
          end

          # Compact a rate limit message.
          # @param text [String]
          # @return [String]
          # 方法功能：压缩速率限制消息
          # 参数：text - 消息文本
          # 返回值：压缩后的消息字符串
          def compact_rate_limit_message(text)
            compact = text.gsub(/\s+/, ' ').strip
            return compact if compact.length <= 360

            "#{compact[0...357].strip}..."
          end
        end
      end
    end
  end
end
