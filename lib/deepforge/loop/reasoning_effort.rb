# frozen_string_literal: true

# 文件用途：模型推理努力级别枚举和标准化工具
# 使用方法：通过 ModelReasoningEffort.safe_parse(value) 安全解析

# 模块功能：模型推理努力级别枚举
# 定义 OFF、HIGH、MAX 三个级别，用于控制模型推理深度
module DeepForge
  module Loop
    module ModelReasoningEffort
      # 关闭推理
      OFF = 'off'
      # 高级推理
      HIGH = 'high'
      # 最大推理
      MAX = 'max'

      # 有效的努力级别列表
      VALUES = [OFF, HIGH, MAX].freeze

      # 安全解析推理努力级别字符串
      # @param value [String] 待验证的字符串
      # @return [String, nil] 有效的推理努力级别或 nil（无效时）
      def self.safe_parse(value)
        return nil unless value.is_a?(String)

        trimmed = value.strip
        VALUES.include?(trimmed) ? trimmed : nil
      end
    end
  end
end

# 标准化角色级别的推理深度配置值
# 无效或缺失的值回退到 'off'，避免廉价默认值意外提升标题/摘要/审查调用的推理深度
#
# @param value [String, nil] 推理努力级别字符串
# @return [String] 有效的 ModelReasoningEffort（off, high, max）
def normalize_role_reasoning_effort(value)
  parsed = DeepForge::Loop::ModelReasoningEffort.safe_parse(value.is_a?(String) ? value.strip : value)
  parsed || DeepForge::Loop::ModelReasoningEffort::OFF
end
