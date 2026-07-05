# frozen_string_literal: true

# 文件用途：Token 经济模式，通过压缩工具描述、结果和响应减少 token 用量
# 使用方法：通过 TokenEconomy.apply_to_request(request, config) 应用到请求

require 'json'

# 模块功能：Token 经济模式
# 通过压缩工具描述、工具结果和响应文本减少 token 用量
module DeepForge
  module Loop
    module TokenEconomy
      module_function

      # 默认配置
      DEFAULT_CONFIG = {
        enabled: false,
        compress_tool_descriptions: true,
        compress_tool_results: true,
        concise_responses: true,
        history_hygiene: {}
      }.freeze

      # Token 经济模式指令，注入给模型以产生简洁响应
      TOKEN_ECONOMY_INSTRUCTION = [
        'Token economy mode is enabled.',
        'Reply concisely: answer directly, skip pleasantries, filler, and hedging.',
        'Preserve exact code, commands, paths, URLs, identifiers, and quoted errors.',
        'When tool output says content was omitted, use narrower read/grep/bash ranges instead of guessing.'
      ].join("\n")

      # 命令输出最大行数
      MAX_COMMAND_LINES = 180
      # 命令输出最大字节数
      MAX_COMMAND_BYTES = 24 * 1024
      # 读取输出最大行数
      MAX_READ_LINES = 320
      # 读取输出最大字节数
      MAX_READ_BYTES = 32 * 1024
      # 通用文本最大行数
      MAX_GENERIC_TEXT_LINES = 220
      # 通用文本最大字节数
      MAX_GENERIC_TEXT_BYTES = 24 * 1024
      # grep 最大匹配数
      MAX_GREP_MATCHES = 80
      # find 最大匹配数
      MAX_FIND_MATCHES = 160
      # ls 最大条目数
      MAX_LS_ENTRIES = 120
      # 数组最大元素数
      MAX_ARRAY_ITEMS = 80
      # 单行最大字符数
      MAX_LINE_CHARS = 260

      # 信号行匹配模式（错误、警告等）
      SIGNAL_LINE_RE = /error|failed?|fatal|panic|exception|traceback|warning|warn|denied|timeout|timed out|not found|cannot|invalid/i
      # 填充词匹配模式
      FILLERS_RE = /\b(?:just|really|basically|actually|simply|quite|very|essentially|literally|generally)\b/i
      # 客套话匹配模式
      PLEASANTRIES_RE = /\b(?:please|kindly|thank you|thanks|sure|certainly|of course|happy to|i'?d be happy)\b[,.]?\s*/i
      # 模糊表达匹配模式
      HEDGES_RE = /\b(?:perhaps|maybe|might|could potentially|would like to|i think|in my opinion|it seems|it appears)\b\s*/i
      # 引导词匹配模式
      LEADERS_RE = /^(?:i'?ll|i will|i can|i'?d|you can|we will|we can|let me|let'?s)\s+/im
      # 冠词匹配模式
      ARTICLES_RE = /\b(?:a|an|the)\s+(?=[a-z])/i

      # 受保护的模式（不会被压缩的内容，如代码块、URL、路径等）
      PROTECTED_PATTERNS = [
        Regexp.new('```[\\s\\S]*?```'),
        Regexp.new('`[^`\\n]+`'),
        Regexp.new('\\bhttps?:\\/\\/\\S+', Regexp::IGNORECASE),
        Regexp.new('\\b[\\w.-]*[/\\\\][\\w./\\\\-]+'),
        Regexp.new('\\b[A-Z][A-Za-z0-9]*(?:_[A-Z][A-Za-z0-9]*)+'),
        Regexp.new('\\b\\w+\\.\\w+(?:\\.\\w+)*\\(\\)'),
        Regexp.new('[A-Za-z_][A-Za-z0-9_]*\\s*\\([^)]*\\)'),
        Regexp.new('\\b\\d+\\.\\d+\\.\\d+')
      ].freeze

      # 标准化 token 经济配置
      # @param input [Hash, nil] 输入配置
      # @return [Hash] 标准化后的配置
      def normalize_config(input)
        config = DEFAULT_CONFIG.dup
        config.merge!(input || {})
        config[:history_hygiene] = (DEFAULT_CONFIG[:history_hygiene] || {}).merge(input&.dig(:history_hygiene) || {})
        config
      end

      # 将 token 经济模式应用到模型请求
      # @param request [Hash] 模型请求
      # @param config [Hash, nil] token 经济配置
      # @return [Hash] 修改后的请求
      def apply_to_request(request, config)
        economy = normalize_config(config)
        return request unless economy[:enabled]

        request.merge(
          context_instructions: if economy[:concise_responses]
                                  ((request[:context_instructions] || []) + [TOKEN_ECONOMY_INSTRUCTION])
                                else
                                  request[:context_instructions]
                                end,
          tools: if economy[:compress_tool_descriptions]
                   (request[:tools] || []).map { |tool| compact_tool_spec(tool) }
                 else
                   request[:tools]
                 end,
          history: if economy[:compress_tool_results]
                     (request[:history] || []).map { |item| compact_history_item(item) }
                   else
                     request[:history]
                   end
        )
      end

      # 压缩工具规范
      # @param tool [Hash] 工具规范
      # @return [Hash] 压缩后的工具规范
      def compact_tool_spec(tool)
        tool.merge(
          description: compress_prose(tool[:description]),
          input_schema: compact_schema_descriptions(tool[:input_schema] || tool['inputSchema'] || {})
        )
      end

      # 压缩历史条目
      # @param item [Hash] 历史条目
      # @return [Hash] 压缩后的条目
      def compact_history_item(item)
        case item[:kind]
        when 'tool_call'
          summary = item[:summary] ? compress_prose(item[:summary]) : item[:summary]
          summary == item[:summary] ? item : item.merge(summary: summary)
        when 'tool_result'
          item.merge(output: compact_tool_output(item[:tool_name] || item[:toolName], item[:output]))
        when 'user_input'
          item.merge(
            questions: (item[:questions] || []).map do |question|
              question.merge(
                question: compress_prose(question[:question]),
                options: (question[:options] || []).map do |option|
                  option.merge(description: compress_prose(option[:description]))
                end
              )
            end
          )
        else
          item
        end
      end

      # 压缩散文文本，去除填充词、客套话和模糊表达
      # @param text [String] 待压缩的文本
      # @return [String] 压缩后的文本
      def compress_prose(text)
        return text if text.strip.empty?

        with_protected_segments(text) do |value|
          out = value
          out = out.gsub(LEADERS_RE, '')
          out = out.gsub(PLEASANTRIES_RE, '')
          out = out.gsub(HEDGES_RE, '')
          out = out.gsub(FILLERS_RE, '')
          out = out.gsub(ARTICLES_RE, '')
          out = out.gsub(/[ \t]{2,}/, ' ')
          out = out.gsub(/\s+([,.;:!?])/, '\1')
          out = out.gsub(/\n{3,}/, "\n\n")
          out = out.gsub(/(^|[.!?]\s+)([a-z])/, '\1\2'.upcase) # Capitalize after sentence endings
          out.strip
        end
      end

      # 在处理文本时保护特定片段不被修改
      # @param text [String] 待处理的文本
      # @yield [String] 转换后的文本
      # @return [String] 处理结果
      def with_protected_segments(text, &block)
        segments = []
        working = text.dup
        PROTECTED_PATTERNS.each do |pattern|
          working = working.gsub(pattern) do |match|
            index = segments.length
            segments << match
            "__DEEPFORGE_PROTECTED_SEGMENT_#{index}__"
          end
        end
        result = block.call(working)
        result.gsub(/__DEEPFORGE_PROTECTED_SEGMENT_(\d+)__/) do
          segments[Regexp.last_match(1).to_i] || ''
        end
      end

      # 压缩 schema 中的描述字段
      # @param value [Object] 待压缩的值
      # @return [Object] 压缩后的 schema
      def compact_schema_descriptions(value)
        case value
        when Array
          value.map { |v| compact_schema_descriptions(v) }
        when Hash
          value.each_with_object({}) do |(key, child), out|
            out[key] = if key == 'description' && child.is_a?(String)
                         compress_prose(child)
                       else
                         compact_schema_descriptions(child)
                       end
          end
        else
          value
        end
      end

      # 根据工具名称压缩工具输出
      # @param tool_name [String] 工具名称
      # @param output [Object] 工具输出
      # @return [Object] 压缩后的输出
      def compact_tool_output(tool_name, output)
        return compact_generic_text(output) if output.is_a?(String)
        return output unless output.is_a?(Hash)

        case tool_name
        when 'bash'
          compact_bash_output(output)
        when 'read'
          compact_read_output(output)
        when 'grep'
          compact_grep_output(output)
        when 'find'
          compact_find_output(output)
        when 'ls'
          compact_ls_output(output)
        else
          compact_generic_value(output)
        end
      end

      # 压缩 bash 命令输出
      # @param output [Hash] bash 输出
      # @return [Hash] 压缩后的输出
      def compact_bash_output(output)
        output.merge(
          output: if output[:output].is_a?(String)
                    compact_command_output(output[:output], output[:full_output_path])
                  else
                    output[:output]
                  end
        )
      end

      # 压缩 read 工具输出
      # @param output [Hash] read 输出
      # @return [Hash] 压缩后的输出
      def compact_read_output(output)
        result = output.dup
        if result[:content].is_a?(String)
          result[:content] = compact_head_text(result[:content], {
                                                 max_lines: MAX_READ_LINES,
                                                 max_bytes: MAX_READ_BYTES,
                                                 label: 'file content'
                                               })
        end
        if result[:data_base64].is_a?(String)
          result[:data_base64] = "[base64 image data omitted by token economy: #{result[:data_base64].length} chars]"
        end
        result
      end

      # 压缩 grep 工具输出
      # @param output [Hash] grep 输出
      # @return [Hash] 压缩后的输出
      def compact_grep_output(output)
        matches = output[:matches].is_a?(Array) ? output[:matches] : []
        result = output.merge(
          matches: matches.first(MAX_GREP_MATCHES).map { |m| compact_grep_match(m) }
        )
        result[:token_economy_omitted_matches] = matches.length - MAX_GREP_MATCHES if matches.length > MAX_GREP_MATCHES
        result
      end

      # 压缩单个 grep 匹配结果
      # @param value [Hash] grep 匹配
      # @return [Hash] 压缩后的匹配
      def compact_grep_match(value)
        return value unless value.is_a?(Hash)

        result = value.dup
        result[:text] = compact_line(result[:text]) if result[:text].is_a?(String)
        result[:context_before] = compact_context_lines(result[:context_before])
        result[:context_after] = compact_context_lines(result[:context_after])
        result
      end

      # 压缩 find 工具输出
      # @param output [Hash] find 输出
      # @return [Hash] 压缩后的输出
      def compact_find_output(output)
        matches = output[:matches].is_a?(Array) ? output[:matches] : []
        result = output.merge(matches: matches.first(MAX_FIND_MATCHES))
        result[:token_economy_omitted_matches] = matches.length - MAX_FIND_MATCHES if matches.length > MAX_FIND_MATCHES
        result
      end

      # 压缩 ls 工具输出
      # @param output [Hash] ls 输出
      # @return [Hash] 压缩后的输出
      def compact_ls_output(output)
        entries = output[:entries].is_a?(Array) ? output[:entries] : []
        names = output[:names].is_a?(Array) ? output[:names] : []
        result = output.merge(
          entries: entries.first(MAX_LS_ENTRIES),
          names: names.first(MAX_LS_ENTRIES)
        )
        result[:token_economy_omitted_entries] = entries.length - MAX_LS_ENTRIES if entries.length > MAX_LS_ENTRIES
        result
      end

      # 压缩通用值
      # @param value [Object] 待压缩的值
      # @param key [String] 键名
      # @return [Object] 压缩后的值
      def compact_generic_value(value, key = '')
        if value.is_a?(String)
          return compress_prose(value) if key == 'description'
          return "[base64 data omitted by token economy: #{value.length} chars]" if key == 'data_base64'
          return compact_generic_text(value) if large_text?(value)

          return value
        end

        if value.is_a?(Array)
          mapped = value.first(MAX_ARRAY_ITEMS).map { |item| compact_generic_value(item) }
          mapped << { token_economy_omitted_items: value.length - MAX_ARRAY_ITEMS } if value.length > MAX_ARRAY_ITEMS
          return mapped
        end

        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(child_key, child_value), out|
          out[child_key] = compact_generic_value(child_value, child_key)
        end
      end

      # 压缩上下文行
      # @param value [Object] 待压缩的值
      # @return [Array] 压缩后的上下文行
      def compact_context_lines(value)
        return value unless value.is_a?(Array)

        value.first(2).map { |line| line.is_a?(String) ? compact_line(line) : line }
      end

      # 压缩命令输出
      # @param text [String] 命令输出
      # @param has_full_output_path [Boolean] 是否有完整输出路径
      # @return [String] 压缩后的输出
      def compact_command_output(text, has_full_output_path)
        normalized = normalize_text_block(text)
        return normalized if fits_text_budget?(normalized, MAX_COMMAND_LINES, MAX_COMMAND_BYTES)

        lines = split_lines(normalized)
        indexes = Set.new
        head_count = [24, (MAX_COMMAND_LINES * 0.15).floor].min
        tail_count = [96, (MAX_COMMAND_LINES * 0.55).floor].min

        head_count.times { |i| indexes.add(i) if i < lines.length }
        tail_count.times do |i|
          idx = lines.length - tail_count + i
          indexes.add(idx) if idx >= 0 && idx < lines.length
        end

        lines.each_with_index do |line, index|
          break if indexes.size >= MAX_COMMAND_LINES

          indexes.add(index) if SIGNAL_LINE_RE.match?(line)
        end

        selected = indexes.sort.map { |i| compact_line(lines[i] || '') }
        fitted = fit_lines_to_budget(selected, MAX_COMMAND_LINES, MAX_COMMAND_BYTES)
        suffix = has_full_output_path ? 'full_output_path retained' : 'run a narrower command or inspect with read/grep'
        (fitted + ["[token economy: showing #{fitted.length} of #{lines.length} lines; #{suffix}]"]).join("\n")
      end

      # 压缩通用文本
      # @param text [String] 通用文本
      # @return [String] 压缩后的文本
      def compact_generic_text(text)
        compact_head_text(text, {
                            max_lines: MAX_GENERIC_TEXT_LINES,
                            max_bytes: MAX_GENERIC_TEXT_BYTES,
                            label: 'text'
                          })
      end

      # 压缩文本头部
      # @param text [String] 待压缩的文本
      # @param options [Hash] 压缩选项
      # @return [String] 压缩后的文本
      def compact_head_text(text, options)
        normalized = normalize_text_block(text)
        return normalized if fits_text_budget?(normalized, options[:max_lines], options[:max_bytes])

        lines = split_lines(normalized).map { |line| compact_line(line) }
        fitted = fit_lines_to_budget(lines, options[:max_lines], options[:max_bytes])
        (fitted + ["[token economy: showing first #{fitted.length} of #{lines.length} #{options[:label]} lines]"]).join("\n")
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

      # 将文本按行分割
      # @param text [String] 待分割的文本
      # @return [Array<String>] 行列表
      def split_lines(text)
        return [] if text.nil? || text.empty?

        text.split("\n")
      end

      # 检查文本是否在预算限制内
      # @param text [String] 待检查的文本
      # @param max_lines [Integer] 最大行数
      # @param max_bytes [Integer] 最大字节数
      # @return [Boolean] 是否在限制内
      def fits_text_budget?(text, max_lines, max_bytes)
        split_lines(text).length <= max_lines && text.bytesize <= max_bytes
      end

      # 将行适配到预算限制内
      # @param lines [Array<String>] 行列表
      # @param max_lines [Integer] 最大行数
      # @param max_bytes [Integer] 最大字节数
      # @return [Array<String>] 适配后的行
      def fit_lines_to_budget(lines, max_lines, max_bytes)
        out = []
        bytes = 0
        lines.each do |line|
          break if out.length >= max_lines

          line_bytes = line.bytesize + (out.empty? ? 0 : 1)
          break if bytes + line_bytes > max_bytes

          out << line
          bytes += line_bytes
        end
        out
      end

      # 压换单行文本
      # @param line [String] 待压缩的行
      # @return [String] 压缩后的行
      def compact_line(line)
        return line.strip if line.length <= MAX_LINE_CHARS

        head = (MAX_LINE_CHARS * 0.6).floor
        tail = MAX_LINE_CHARS - head - 5
        "#{line[0, head].rstrip} ... #{line[-tail, tail]&.lstrip}"
      end

      # 检查文本是否为大文本
      # @param text [String] 待检查的文本
      # @return [Boolean] 是否为大文本
      def large_text?(text)
        text.length > MAX_GENERIC_TEXT_BYTES || split_lines(text).length > MAX_GENERIC_TEXT_LINES
      end
    end
  end
end
