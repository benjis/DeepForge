# frozen_string_literal: true

# 文件用途：工具风暴断路器，防止重复相同工具调用膨胀动态历史和缓存未命中
# 使用方法：通过 ToolStormBreaker.new(options) 创建实例
# 断路器故意限定为轮次范围；新用户轮次是新意图，AgentLoop 在轮次间重置断路器

require 'json'

# 类功能：工具风暴断路器
# 检测并抑制重复的相同工具调用，防止循环调用导致的性能问题
module DeepForge
  module Loop
    class ToolStormBreaker
      # 默认窗口大小
      DEFAULT_WINDOW_SIZE = 8
      # 默认抑制阈值
      DEFAULT_THRESHOLD = 3
      # 修改性工具名称列表
      MUTATING_TOOL_NAMES = %w[write edit edit_diff apply_patch delete move].freeze
      # 风暴豁免工具名称列表
      STORM_EXEMPT_TOOL_NAMES = %w[request_user_input user_input].freeze

      # 初始化工具风暴断路器
      # @param options [Hash] 配置选项
      # @option options [Integer] :window_size 窗口大小
      # @option options [Integer] :threshold 抑制阈值
      def initialize(options = {})
        @window_size = [1, (options[:window_size] || DEFAULT_WINDOW_SIZE).to_i].max
        @threshold = [2, (options[:threshold] || DEFAULT_THRESHOLD).to_i].max
        @recent = []
      end

      # 检查工具调用是否触发风暴条件
      # @param call [Hash] 工具调用
      # @return [Hash] { suppress: Boolean, reason: String } 是否抑制和原因
      def inspect(call)
        return { suppress: false } if STORM_EXEMPT_TOOL_NAMES.include?(call[:tool_name])

        name = call[:tool_name]
        args = stable_stringify(call[:arguments])
        read_only = !mutating_tool_call?(call)

        clear_read_only_entries unless read_only

        count = @recent.count { |entry| entry[:name] == name && entry[:args] == args }
        if count >= @threshold - 1
          return {
            suppress: true,
            reason: "#{name} was called with identical arguments #{count + 1} times in this turn; " \
                    'repeat-loop guard suppressed the duplicate. Choose a narrower query or explain why another identical call is needed.'
          }
        end

        @recent.push({ name: name, args: args, read_only: read_only })
        @recent.shift while @recent.length > @window_size

        { suppress: false }
      end

      # 重置断路器
      def reset
        @recent.clear
      end

      private

      # 判断工具调用是否为修改性调用
      # @param call [Hash] 工具调用
      # @return [Boolean] 是否为修改性调用
      def mutating_tool_call?(call)
        return true if call[:tool_kind] == 'file_change'

        MUTATING_TOOL_NAMES.include?(call[:tool_name])
      end

      # 清除最近调用中的只读条目
      def clear_read_only_entries
        @recent.reject! { |entry| entry[:read_only] }
      end

      # 将值稳定地序列化为 JSON 字符串
      # @param value [Object] 待序列化的值
      # @return [String] 稳定的 JSON 字符串
      def stable_stringify(value)
        JSON.generate(canonicalize(value))
      rescue StandardError
        value.to_s
      end

      # 规范化值（键排序的哈希）
      # @param value [Object] 待规范化的值
      # @return [Object] 键排序后的规范化值
      def canonicalize(value)
        case value
        when Array
          value.map { |v| canonicalize(v) }
        when Hash
          value.each_with_object({}) { |(k, v), out| out[k] = canonicalize(v) }
               .sort.to_h
        else
          value
        end
      end
    end
  end
end
