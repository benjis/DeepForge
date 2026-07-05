# frozen_string_literal: true

# 文件用途：密钥脱敏工具模块
# 使用方法：在日志记录或调试输出前，对包含 API 密钥、令牌等敏感信息的字符串进行脱敏处理。
#           支持键名匹配脱敏和文本模式匹配脱敏。

module DeepForge
  module Config
    # 密钥脱敏工具模块，用于安全的日志记录。
    module SecretRedaction
      # 匹配敏感键名的正则表达式模式
      SECRET_KEY_PATTERN = /(api[-_]?key|authorization|bearer|client[-_]?secret|password|secret|token)/i
      # 匹配敏感文本内容的正则表达式模式
      SECRET_TEXT_PATTERNS = [
        /\b(authorization|api[-_]?key|client[-_]?secret|password|token)\s*[:=]\s*((?:Bearer\s+)?[^\s,;]+)/i,
        /\bbearer\s+([^\s,;]+)/i
      ].freeze

      # 脱敏后的占位符文本
      REDACTED_SECRET = '<redacted>'

      module_function

      # 对值进行密钥脱敏处理（入口方法）
      # 参数：value - 待脱敏的值（支持 Hash、Array、String 类型）
      # 返回值：脱敏后的值
      def redact_secrets(value)
        redact(value)
      end

      # 递归脱敏处理，根据键名和值类型分别处理
      # 参数：value - 待脱敏的值，key - 当前键名（用于判断是否为敏感键）
      # 返回值：脱敏后的值
      def redact(value, key = '')
        return value.map { |item| redact(item) } if value.is_a?(Array)

        unless value.is_a?(Hash)
          return value unless value.is_a?(String)
          return REDACTED_SECRET if SECRET_KEY_PATTERN.match?(key)

          return redact_secret_text(value)
        end

        out = {}
        value.each do |child_key, child_value|
          out[child_key] = if SECRET_KEY_PATTERN.match?(child_key)
                             REDACTED_SECRET
                           else
                             redact(child_value, child_key)
                           end
        end
        out
      end

      # 对字符串中的敏感文本模式进行脱敏
      # 参数：value - 待处理的字符串
      # 返回值：String，脱敏后的字符串
      def redact_secret_text(value)
        result = value.dup
        SECRET_TEXT_PATTERNS.each do |pattern|
          result = result.gsub(pattern) do |match|
            key = Regexp.last_match(1)
            if match.downcase.start_with?('bearer ')
              "Bearer #{REDACTED_SECRET}"
            else
              "#{key}=#{REDACTED_SECRET}"
            end
          end
        end
        result
      end
    end
  end
end
