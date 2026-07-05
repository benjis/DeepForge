# frozen_string_literal: true

# 文件用途：工具调用参数修复模块，处理已解析的工具参数中的问题
# 使用方法：通过 ToolCallRepair.repair(raw, options) 调用
# 模型适配器在解析提供商载荷时修复 JSON 字符串；此边界检查处理
# 仍以哈希形式到达循环的提供商无关形状

require 'json'

# 模块功能：工具调用参数修复
# 处理包裹的参数、JSON 字符串和超大字符串等问题
module DeepForge
  module Loop
    module ToolCallRepair
      module_function

      # 默认最大字符串字节数
      DEFAULT_MAX_STRING_BYTES = 512 * 1024
      # 可展平的包装器键名
      WRAPPER_KEYS = %w[arguments args input parameters params payload __raw].freeze
      # 工具元数据键名
      TOOL_METADATA_KEYS = %w[tool toolName tool_name name id callId call_id type].freeze

      # 修复原始工具参数
      # @param raw [Hash] 原始工具参数
      # @param options [Hash] 修复选项
      # @option options [String] :tool_name 工具名称
      # @option options [String] :tool_kind 工具类型
      # @option options [Integer] :max_string_bytes 最大字符串字节数
      # @return [Hash] { arguments: Hash, notes: Array<String> } 修复后的参数和修复说明
      def repair(raw, options = {})
        notes = []
        current = shallow_clone_record(raw)

        flattened = flatten_wrapper(current)
        if flattened
          current = flattened[:arguments]
          notes << flattened[:note]
        else
          scavenged = scavenge_single_json_string(current)
          if scavenged
            current = scavenged[:arguments]
            notes << scavenged[:note]
          end
        end

        truncated = truncate_oversized_strings(current, {
                                                 max_string_bytes: options[:max_string_bytes] || DEFAULT_MAX_STRING_BYTES,
                                                 preserve_long_strings: options[:tool_kind] == 'file_change'
                                               })
        if truncated[:changed]
          current = truncated[:value]
          notes << "truncated #{truncated[:count]} oversized argument string(s)"
        end

        { arguments: current, notes: notes }
      end

      # 浅拷贝记录
      # @param value [Hash] 待克隆的记录
      # @return [Hash] 浅拷贝
      def shallow_clone_record(value)
        value.dup
      end

      # 展平包装器参数
      # @param raw [Hash] 原始参数
      # @return [Hash, nil] 展平后的参数或 nil
      def flatten_wrapper(raw)
        WRAPPER_KEYS.each do |key|
          next unless raw.key?(key)
          next unless can_flatten_wrapper?(raw, key)

          value = raw[key]
          parsed = value_to_object(value)
          next unless parsed

          return { arguments: parsed, note: "flattened #{key} wrapper" }
        end
        nil
      end

      # 判断包装器是否可以展平
      # @param raw [Hash] 原始参数
      # @param wrapper_key [String] 包装器键名
      # @return [Boolean] 是否可以展平
      def can_flatten_wrapper?(raw, wrapper_key)
        keys = raw.keys
        return true if keys.length == 1

        keys.all? { |key| key == wrapper_key || TOOL_METADATA_KEYS.include?(key) }
      end

      # 从单个 JSON 字符串中提取参数
      # @param raw [Hash] 原始参数
      # @return [Hash, nil] 提取的参数或 nil
      def scavenge_single_json_string(raw)
        entries = raw.to_a
        return nil unless entries.length == 1

        key, value = entries.first
        return nil unless key && value.is_a?(String)

        parsed = parse_jsonish_object(value)
        return nil unless parsed

        { arguments: parsed, note: "scavenged JSON object from #{key}" }
      end

      # 将值转换为对象
      # @param value [Object] 待转换的值
      # @return [Hash, nil] 对象或 nil
      def value_to_object(value)
        return value.dup if value.is_a?(Hash)
        return parse_jsonish_object(value) if value.is_a?(String)

        nil
      end

      # 解析类 JSON 文本为对象
      # @param text [String] 待解析的文本
      # @return [Hash, nil] 解析后的对象或 nil
      def parse_jsonish_object(text)
        candidates = [
          text.strip,
          strip_markdown_fence(text.strip),
          extract_first_json_object(text)
        ].compact.reject { |c| c.strip.empty? }

        candidates.each do |candidate|
          parsed = JSON.parse(candidate)
          return parsed.dup if parsed.is_a?(Hash)
        rescue JSON::ParserError
          # Try next candidate
        end
        nil
      end

      # 截断超大字符串
      # @param value [Hash] 待截断的值
      # @param options [Hash] 截断选项
      # @return [Hash] { value: Hash, changed: Boolean, count: Integer }
      def truncate_oversized_strings(value, options)
        return { value: value, changed: false, count: 0 } if options[:preserve_long_strings]

        state = { changed: false, count: 0 }
        next_val = truncate_value(value, options[:max_string_bytes], state)
        {
          value: next_val.is_a?(Hash) ? next_val : value,
          changed: state[:changed],
          count: state[:count]
        }
      end

      # 递归截断值中的超大字符串
      # @param value [Object] 待截断的值
      # @param max_bytes [Integer] 最大字节数
      # @param state [Hash] 状态追踪器
      # @return [Object] 截断后的值
      def truncate_value(value, max_bytes, state)
        if value.is_a?(String)
          return value if value.bytesize <= max_bytes

          state[:changed] = true
          state[:count] += 1
          return "#{slice_utf8(value, max_bytes)}\n...[truncated by DeepForge tool argument repair]"
        end

        return value.map { |item| truncate_value(item, max_bytes, state) } if value.is_a?(Array)

        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, child), out|
          out[key] = truncate_value(child, max_bytes, state)
        end
      end

      # 去除 markdown 围栏
      # @param text [String] 待处理的文本
      # @return [String] 去除围栏后的文本
      def strip_markdown_fence(text)
        match = text.match(/^```(?:json|javascript|js)?\s*(.*?)\s*```$/im)
        match ? match[1].strip : text
      end

      # 从文本中提取第一个 JSON 对象
      # @param text [String] 待提取的文本
      # @return [String, nil] 第一个 JSON 对象或 nil
      def extract_first_json_object(text)
        start_idx = text.index('{')
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

          depth += 1 if char == '{'
          if char == '}'
            depth -= 1
            return text[start_idx..index] if depth.zero?
          end
        end
        nil
      end

      # 按字节截断 UTF-8 字符串
      # @param value [String] 待截断的字符串
      # @param max_bytes [Integer] 最大字节数
      # @return [String] 截断后的字符串
      def slice_utf8(value, max_bytes)
        bytes = value.bytes
        used = 0
        out = ''
        bytes.each do |byte|
          break if used + 1 > max_bytes

          out += byte.chr
          used += 1
        end
        out
      end
    end
  end
end
