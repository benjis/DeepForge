# frozen_string_literal: true

# 文件用途：工具调用参数修复模块
# 使用方法：当模型输出的工具调用参数为格式不正确的 JSON 时，尝试多种修复策略：
#           去除 Markdown 围栏、提取第一个 JSON 对象/数组、使用平衡括号提取等。

require 'json'

module DeepForge
  module Adapters
    module Model
      # 修复模型输出中格式不正确的 JSON 工具调用参数。
      module ToolArgumentRepair
        module_function

        # 修复模型输出的格式不正确的工具调用参数 JSON
        # 参数：raw - 原始参数字符串
        # 返回值：Hash（含 :arguments 和 :repaired 键），arguments 为解析后的参数哈希，
        #          repaired 表示是否经过修复
        def repair_tool_arguments(raw)
          trimmed = raw.strip
          return { arguments: {}, repaired: false } if trimmed.empty?

          direct = parse_object(trimmed)
          return { arguments: direct, repaired: false } if direct

          candidates = [
            strip_markdown_fence(trimmed),
            extract_first_json_object(trimmed),
            extract_first_json_array(trimmed)
          ].compact.reject { |c| c.strip.empty? }

          candidates.each do |candidate|
            parsed = parse_any(candidate)
            if parsed[:ok]
              return {
                arguments: value_to_arguments(parsed[:value]),
                repaired: true
              }
            end
          end

          { arguments: { __raw: raw }, repaired: false }
        end

        # 尝试将文本解析为 JSON 对象
        # 参数：text - 待解析的文本
        # 返回值：Hash 或 nil，解析成功返回对象，失败返回 nil
        def parse_object(text)
          parsed = parse_any(text)
          return nil unless parsed[:ok]

          value = parsed[:value]
          return unless value.is_a?(Hash) && !value.is_a?(Array)

          value
        end

        # 尝试将文本解析为任意 JSON 值
        # 参数：text - 待解析的文本
        # 返回值：Hash（含 :ok 和 :value 键）
        def parse_any(text)
          { ok: true, value: JSON.parse(text) }
        rescue JSON::ParserError
          { ok: false }
        end

        # 将解析后的值转换为工具参数格式（确保为 Hash）
        # 参数：value - JSON 解析后的值
        # 返回值：Hash，工具参数
        def value_to_arguments(value)
          if value.is_a?(Hash) && !value.is_a?(Array)
            value
          else
            { value: value }
          end
        end

        # 去除 Markdown 代码围栏（```json ... ```）
        # 参数：text - 可能包含围栏的文本
        # 返回值：String，去除围栏后的文本
        def strip_markdown_fence(text)
          match = text.match(/^```(?:json|javascript|js)?\s*([\s\S]*?)\s*```$/i)
          match ? match[1].strip : text
        end

        # 从文本中提取第一个完整的 JSON 对象
        # 参数：text - 待提取的文本
        # 返回值：String 或 nil，提取到的 JSON 对象字符串
        def extract_first_json_object(text)
          extract_balanced(text, '{', '}')
        end

        # 从文本中提取第一个完整的 JSON 数组
        # 参数：text - 待提取的文本
        # 返回值：String 或 nil，提取到的 JSON 数组字符串
        def extract_first_json_array(text)
          extract_balanced(text, '[', ']')
        end

        # 通过平衡括号匹配提取文本中第一个完整的结构
        # 参数：text - 待提取的文本，open_char - 开括号，close_char - 闭括号
        # 返回值：String 或 nil，提取到的完整结构字符串
        def extract_balanced(text, open_char, close_char)
          start_idx = text.index(open_char)
          return nil unless start_idx

          depth = 0
          in_string = false
          escaped = false

          (start_idx...text.length).each do |index|
            char = text[index]

            if escaped
              escaped = false
              next
            end

            if char == '\\'
              escaped = true
              next
            end

            if char == '"'
              in_string = !in_string
              next
            end

            next if in_string

            depth += 1 if char == open_char
            if char == close_char
              depth -= 1
              return text[start_idx..index] if depth.zero?
            end
          end

          nil
        end
      end
    end
  end
end
