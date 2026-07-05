# frozen_string_literal: true

# 文件用途：请求历史卫生处理，在发送时压缩动态工具历史而不修改持久化的会话日志
# 使用方法：通过 RequestHistoryHygiene.apply(items, options) 调用
# 保持动态工具历史有界，使预热的不可变前缀在每次请求中占更大比例

# 模块功能：请求历史卫生处理
# 在发送时压缩工具结果和参数，保持历史有界
module DeepForge
  module Loop
    module RequestHistoryHygiene
      module_function

      # 工具结果最大行数
      DEFAULT_MAX_TOOL_RESULT_LINES = 320
      # 工具结果最大字节数
      DEFAULT_MAX_TOOL_RESULT_BYTES = 32 * 1024
      # 工具结果最大 token 数
      DEFAULT_MAX_TOOL_RESULT_TOKENS = 8_000
      # 工具参数字符串最大字节数
      DEFAULT_MAX_TOOL_ARGUMENT_STRING_BYTES = 8 * 1024
      # 工具参数字符串最大 token 数
      DEFAULT_MAX_TOOL_ARGUMENT_STRING_TOKENS = 2_000
      # 数组最大元素数
      DEFAULT_MAX_ARRAY_ITEMS = 80
      # 信号行最大数量
      MAX_SIGNAL_LINES = 48
      # 单行最大字符数
      MAX_LINE_CHARS = 280
      # 长参数预览字符数
      LONG_ARGUMENT_PREVIEW_CHARS = 160

      # 信号行匹配模式（错误、警告等）
      SIGNAL_LINE_RE = /error|failed?|fatal|panic|exception|traceback|warning|warn|denied|timeout|timed out|not found|cannot|invalid/i
      # Base64 键匹配模式
      BASE64_KEY_RE = /(?:^|_)(?:data_)?base64$/i
      # Data URL 匹配模式
      DATA_URL_RE = /^data:[^;,]+;base64,/i

      # 对历史条目应用卫生处理
      # @param items [Array<Hash>] 历史条目
      # @param options [Hash] 卫生处理选项
      # @return [Array<Hash>] 处理后的条目
      def apply(items, options = {})
        limits = normalize_options(options)
        paired_tool_call_ids = items
                               .select { |item| item[:kind] == 'tool_result' }
                               .to_set { |item| item[:call_id] || item[:callId] }

        changed = false
        next_items = items.map do |item|
          if item[:kind] == 'tool_result'
            output = compact_tool_result_output(item[:output], limits)
            next item unless output[:changed]

            changed = true
            item.merge(output: output[:value])
          elsif item[:kind] == 'tool_call' && paired_tool_call_ids.include?(item[:call_id] || item[:callId])
            args = compact_completed_tool_arguments(item[:arguments], {
                                                      tool_name: item[:tool_name] || item[:toolName],
                                                      max_string_bytes: limits[:max_tool_argument_string_bytes],
                                                      max_string_tokens: limits[:max_tool_argument_string_tokens],
                                                      max_array_items: limits[:max_array_items]
                                                    })
            next item unless args[:changed]

            changed = true
            item.merge(arguments: args[:value])
          else
            item
          end
        end

        changed ? next_items : items
      end

      # 标准化卫生处理选项，填充默认值
      # @param options [Hash] 选项
      # @return [Hash] 标准化后的选项
      def normalize_options(options)
        {
          max_tool_result_lines: [1, (options[:max_tool_result_lines] || DEFAULT_MAX_TOOL_RESULT_LINES).to_i].max,
          max_tool_result_bytes: [512, (options[:max_tool_result_bytes] || DEFAULT_MAX_TOOL_RESULT_BYTES).to_i].max,
          max_tool_result_tokens: [128,
                                   (options[:max_tool_result_tokens] || DEFAULT_MAX_TOOL_RESULT_TOKENS).to_i].max,
          max_tool_argument_string_bytes: [512,
                                           (options[:max_tool_argument_string_bytes] || DEFAULT_MAX_TOOL_ARGUMENT_STRING_BYTES).to_i].max,
          max_tool_argument_string_tokens: [128,
                                            (options[:max_tool_argument_string_tokens] || DEFAULT_MAX_TOOL_ARGUMENT_STRING_TOKENS).to_i].max,
          max_array_items: [1, (options[:max_array_items] || DEFAULT_MAX_ARRAY_ITEMS).to_i].max
        }
      end

      # 压缩工具结果输出
      # @param output [Object] 工具结果输出
      # @param limits [Hash] 限制配置
      # @return [Hash] { value: Object, changed: Boolean } 压缩后的值和是否变更
      def compact_tool_result_output(output, limits)
        compact_tool_result_value(output, '', limits)
      end

      # 压缩工具结果值（递归处理字符串、数组、哈希）
      # @param value [Object] 待压缩的值
      # @param key [String] 键名
      # @param limits [Hash] 限制配置
      # @return [Hash] { value: Object, changed: Boolean }
      def compact_tool_result_value(value, key, limits)
        if value.is_a?(String)
          if should_omit_base64?(key, value)
            return {
              value: "[cache hygiene: omitted base64 data, #{format_bytes(value.bytesize)}]",
              changed: true
            }
          end
          return compact_tool_result_text(value, limits)
        end

        return compact_array(value, limits) if value.is_a?(Array)

        return { value: value, changed: false } unless value.is_a?(Hash)

        changed = false
        out = {}
        value.each do |child_key, child_value|
          child = compact_tool_result_value(child_value, child_key, limits)
          out[child_key] = child[:value]
          changed = true if child[:changed]
        end
        changed ? { value: out, changed: true } : { value: value, changed: false }
      end

      # 压缩数组，保留头部和尾部元素
      # @param values [Array] 待压缩的数组
      # @param limits [Hash] 限制配置
      # @return [Hash] { value: Array, changed: Boolean }
      def compact_array(values, limits)
        keep_head = [1, (limits[:max_array_items] * 0.75).floor].max
        keep_tail = [0, limits[:max_array_items] - keep_head].max
        tail = keep_tail.positive? ? values.last(keep_tail) : []

        selected = if values.length > limits[:max_array_items]
                     values.first(keep_head) + [{ cache_hygiene_omitted_items: values.length - limits[:max_array_items] }] + tail
                   else
                     values
                   end

        changed = selected != values
        out = selected.map do |value|
          compacted = compact_tool_result_value(value, '', limits)
          changed = true if compacted[:changed]
          compacted[:value]
        end
        changed ? { value: out, changed: true } : { value: values, changed: false }
      end

      # 压缩工具结果文本，选择对缓存有用的行
      # @param text [String] 工具结果文本
      # @param limits [Hash] 限制配置
      # @return [Hash] { value: String, changed: Boolean }
      def compact_tool_result_text(text, limits)
        original_bytes = text.bytesize
        original_lines = count_lines(text)
        original_tokens = estimate_tokens(text)

        if original_bytes <= limits[:max_tool_result_bytes] &&
           original_lines <= limits[:max_tool_result_lines] &&
           original_tokens <= limits[:max_tool_result_tokens]
          return { value: text, changed: false }
        end

        normalized = normalize_text_block(text)
        lines = normalized ? normalized.split("\n") : []
        selected = select_cache_useful_lines(lines, limits[:max_tool_result_lines])
        omitted_bytes = [0, original_bytes - selected.join("\n").bytesize].max
        selected_tokens = estimate_tokens(selected.join("\n"))
        omitted_tokens = [0, original_tokens - selected_tokens].max

        marker = "[cache hygiene: omitted #{[0, lines.length - selected.length].max} line(s), " \
                 "#{format_bytes(omitted_bytes)}, approx #{omitted_tokens} token(s); use narrower read/grep/bash ranges for details]"
        budget_for_text = [0, limits[:max_tool_result_bytes] - marker.bytesize - 1].max
        budget_for_tokens = [0, limits[:max_tool_result_tokens] - estimate_tokens(marker) - 1].max

        fitted = fit_lines_to_budget(selected.map { |line| compact_line(line) }, {
                                       max_bytes: budget_for_text,
                                       max_tokens: budget_for_tokens
                                     })

        { value: (fitted + [marker]).join("\n"), changed: true }
      end

      # 选择对缓存有用的行（保留头部、尾部和信号行）
      # @param lines [Array<String>] 行列表
      # @param max_lines [Integer] 最大行数
      # @return [Array<String>] 选中的行
      def select_cache_useful_lines(lines, max_lines)
        return lines if lines.length <= max_lines

        indexes = Set.new
        head_count = [80, [1, (max_lines * 0.25).floor].max].min
        tail_count = [120, [1, (max_lines * 0.35).floor].max].min

        head_count.times { |i| indexes.add(i) if i < lines.length }
        tail_count.times do |i|
          idx = lines.length - tail_count + i
          indexes.add(idx) if idx >= 0 && idx < lines.length
        end

        signal_count = 0
        lines.each_with_index do |line, index|
          break if indexes.size >= max_lines
          next unless SIGNAL_LINE_RE.match?(line)

          indexes.add(index)
          signal_count += 1
          break if signal_count >= MAX_SIGNAL_LINES
        end

        indexes.sort.first(max_lines).map { |i| lines[i] || '' }
      end

      # 压缩已完成的工具调用参数
      # @param args [Hash] 工具参数
      # @param options [Hash] 压缩选项
      # @return [Hash] { value: Hash, changed: Boolean }
      def compact_completed_tool_arguments(args, options)
        changed = false
        out = {}
        args.each do |key, value|
          compacted = compact_argument_value(value, key, options)
          out[key] = compacted[:value]
          changed = true if compacted[:changed]
        end
        changed ? { value: out, changed: true } : { value: args, changed: false }
      end

      # 压缩单个参数值
      # @param value [Object] 参数值
      # @param key [String] 参数键
      # @param options [Hash] 压缩选项
      # @return [Hash] { value: Object, changed: Boolean }
      def compact_argument_value(value, key, options)
        if value.is_a?(String)
          bytes = value.bytesize
          tokens = estimate_tokens(value)
          if bytes <= options[:max_string_bytes] && tokens <= options[:max_string_tokens]
            return { value: value, changed: false }
          end

          preview = value[0, LONG_ARGUMENT_PREVIEW_CHARS].gsub(/\s+/, ' ').strip
          suffix = preview ? " preview=#{preview.inspect}" : ''
          return {
            value: "[cache hygiene: omitted completed #{options[:tool_name]}.#{key} argument, " \
                   "#{format_bytes(bytes)}, approx #{tokens} token(s), #{count_lines(value)} line(s); see following tool result]#{suffix}",
            changed: true
          }
        end

        if value.is_a?(Array)
          if value.length <= options[:max_array_items]
            changed = false
            out = value.map do |child|
              compacted = compact_argument_value(child, key, options)
              changed = true if compacted[:changed]
              compacted[:value]
            end
            return changed ? { value: out, changed: true } : { value: value, changed: false }
          end
          return {
            value: value.first([1, options[:max_array_items] - 1].max) +
                   [{ cache_hygiene_omitted_items: value.length - options[:max_array_items] }],
            changed: true
          }
        end

        return { value: value, changed: false } unless value.is_a?(Hash)

        changed = false
        out = {}
        value.each do |child_key, child_value|
          compacted = compact_argument_value(child_value, child_key, options)
          out[child_key] = compacted[:value]
          changed = true if compacted[:changed]
        end
        changed ? { value: out, changed: true } : { value: value, changed: false }
      end

      # 判断是否应省略 base64 数据
      # @param key [String] 键名
      # @param value [String] 值
      # @return [Boolean] 是否应省略
      def should_omit_base64?(key, value)
        value.length > 256 && (BASE64_KEY_RE.match?(key) || DATA_URL_RE.match?(value))
      end

      # 规范化文本块，去除重复行和多余空行
      # @param text [String] 待规范化的文本
      # @return [String] 规范化后的文本
      def normalize_text_block(text)
        stripped = text.gsub("\r\n", "\n")
        lines = stripped.split("\n").map(&:rstrip)
        out = []
        blank_run = 0
        previous = ''
        repeat_count = 0

        flush_repeat = proc do
          out << "[previous line repeated #{repeat_count - 1} time(s)]" if repeat_count > 1
          repeat_count = 0
        end

        lines.each do |line|
          if line.strip.empty?
            flush_repeat.call
            blank_run += 1
            out << '' if blank_run <= 2
            previous = ''
            next
          end
          blank_run = 0
          if line == previous
            repeat_count += 1
            next
          end
          flush_repeat.call
          out << line
          previous = line
          repeat_count = 1
        end
        flush_repeat.call
        out.join("\n").strip
      end

      # 将行适配到预算限制内
      # @param lines [Array<String>] 行列表
      # @param budget [Hash] 预算配置
      # @return [Array<String>] 适配后的行
      def fit_lines_to_budget(lines, budget)
        out = []
        bytes = 0
        tokens = 0
        lines.each do |line|
          line_bytes = line.bytesize + (out.empty? ? 0 : 1)
          line_tokens = estimate_tokens(line) + (out.empty? ? 0 : 1)
          break if bytes + line_bytes > budget[:max_bytes] || tokens + line_tokens > budget[:max_tokens]

          out << line
          bytes += line_bytes
          tokens += line_tokens
        end
        if out.empty? && !lines.empty? && budget[:max_bytes].positive? && budget[:max_tokens].positive?
          out << truncate_string_to_budget(lines.first, budget)
        end
        out
      end

      # 压换单行文本
      # @param line [String] 待压缩的行
      # @return [String] 压缩后的行
      def compact_line(line)
        trimmed = line.rstrip
        return trimmed if trimmed.length <= MAX_LINE_CHARS

        head = (MAX_LINE_CHARS * 0.6).floor
        tail = [0, MAX_LINE_CHARS - head - 5].max
        "#{trimmed[0, head].rstrip} ... #{trimmed[-tail, tail]&.lstrip}"
      end

      # 将文本截断到最大字节数
      # @param text [String] 待截断的文本
      # @param max_bytes [Integer] 最大字节数
      # @return [String] 截断后的文本
      def truncate_string_to_bytes(text, max_bytes)
        buffer = text.bytes
        return text if buffer.length <= max_bytes

        end_idx = max_bytes
        end_idx -= 1 while end_idx.positive? && (buffer[end_idx] & 0xc0) == 0x80
        buffer[0, end_idx].pack('C*').force_encoding('UTF-8')
      end

      # 将文本截断到预算限制
      # @param text [String] 待截断的文本
      # @param budget [Hash] 预算配置
      # @return [String] 截断后的文本
      def truncate_string_to_budget(text, budget)
        out = ''
        bytes = 0
        tokens = 0
        text.each_char do |char|
          char_bytes = char.bytesize
          char_tokens = estimate_tokens(char)
          break if bytes + char_bytes > budget[:max_bytes] || tokens + char_tokens > budget[:max_tokens]

          out += char
          bytes += char_bytes
          tokens += char_tokens
        end
        out.empty? ? truncate_string_to_bytes(text, budget[:max_bytes]) : out
      end

      # 计算文本的行数
      # @param text [String] 待计算的文本
      # @return [Integer] 行数
      def count_lines(text)
        return 0 if text.nil? || text.empty?

        lines = text.split("\n")
        text.end_with?("\n") ? lines.length - 1 : lines.length
      end

      # 格式化字节数为可读字符串
      # @param bytes [Integer] 字节数
      # @return [String] 格式化后的字符串
      def format_bytes(bytes)
        return "#{bytes}B" if bytes < 1024
        return "#{(bytes / 1024.0).round(1)}KB" if bytes < 1024 * 1024

        "#{(bytes / (1024.0 * 1024)).round(1)}MB"
      end

      # 估算文本的 token 数量
      # @param text [String] 待估算的文本
      # @return [Integer] 估算的 token 数
      def estimate_tokens(text)
        return 0 if text.nil? || text.empty?

        ascii_run = 0
        tokens = 0

        text.each_char do |char|
          if char.ord <= 0x7f
            ascii_run += 1
            next
          end
          tokens += (ascii_run / 4.0).ceil if ascii_run.positive?
          ascii_run = 0
          tokens += 1 unless combining_mark?(char)
        end
        tokens += (ascii_run / 4.0).ceil if ascii_run.positive?
        [1, tokens].max
      end

      # 检查字符是否为组合标记
      # @param char [String] 待检查的字符
      # @return [Boolean] 是否为组合标记
      def combining_mark?(char)
        char.match?(/[\u0300-\u036f\ufe00-\ufe0f]/)
      end
    end
  end
end
