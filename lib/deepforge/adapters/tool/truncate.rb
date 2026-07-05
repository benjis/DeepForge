# frozen_string_literal: true

# 文件用途：输出截断模块
# 使用方法：通过 Truncate 模块对过长的文本内容进行截断处理

module DeepForge
  module Adapters
    module Tool
      # 默认截断限制
      DEFAULT_MAX_LINES = 2000
      DEFAULT_MAX_BYTES = 50 * 1024

      # 截断结果结构体
      TruncationResult = Struct.new(
        :content, :truncated, :truncated_by, :total_lines, :total_bytes,
        :output_lines, :output_bytes, :last_line_partial, :first_line_exceeds_limit,
        :max_lines, :max_bytes,
        keyword_init: true
      )

      # 截断选项结构体
      TruncationOptions = Struct.new(:max_lines, :max_bytes, keyword_init: true)

      # 模块功能：提供输出截断功能，支持从头部或尾部截断
      module Truncate
        # 方法功能：将字节数格式化为人类可读的字符串
        # 参数：bytes - 字节数
        # 返回值：格式化后的字符串（如 '1.5KB'）
        def self.format_size(bytes)
          if bytes < 1024
            "#{bytes}B"
          elsif bytes < 1024 * 1024
            "#{format('%.1f', bytes / 1024.0)}KB"
          else
            "#{format('%.1f', bytes / (1024.0 * 1024.0))}MB"
          end
        end

        # Truncate from the beginning of content.
        # @param content [String]
        # @param max_lines [Integer]
        # @param max_bytes [Integer]
        # @return [TruncationResult]
        # 方法功能：从内容头部进行截断
        # 参数：content - 内容字符串，max_lines - 最大行数，max_bytes - 最大字节数
        # 返回值：TruncationResult 结构体实例
        def self.truncate_head(content, max_lines: DEFAULT_MAX_LINES, max_bytes: DEFAULT_MAX_BYTES)
          total_bytes = content.bytesize
          lines = split_lines_for_counting(content)
          total_lines = lines.length

          if total_lines <= max_lines && total_bytes <= max_bytes
            return TruncationResult.new(
              content: content,
              truncated: false,
              truncated_by: nil,
              total_lines: total_lines,
              total_bytes: total_bytes,
              output_lines: total_lines,
              output_bytes: total_bytes,
              last_line_partial: false,
              first_line_exceeds_limit: false,
              max_lines: max_lines,
              max_bytes: max_bytes
            )
          end

          first_line_bytes = (lines[0] || '').bytesize
          if first_line_bytes > max_bytes
            return TruncationResult.new(
              content: '',
              truncated: true,
              truncated_by: 'bytes',
              total_lines: total_lines,
              total_bytes: total_bytes,
              output_lines: 0,
              output_bytes: 0,
              last_line_partial: false,
              first_line_exceeds_limit: true,
              max_lines: max_lines,
              max_bytes: max_bytes
            )
          end

          output_lines = []
          output_bytes = 0
          truncated_by = 'lines'

          lines.each_with_index do |line, index|
            break if index >= max_lines

            line_bytes = line.bytesize + (index.positive? ? 1 : 0)
            if output_bytes + line_bytes > max_bytes
              truncated_by = 'bytes'
              break
            end

            output_lines << line
            output_bytes += line_bytes
          end

          output_content = output_lines.join("\n")
          TruncationResult.new(
            content: output_content,
            truncated: true,
            truncated_by: truncated_by,
            total_lines: total_lines,
            total_bytes: total_bytes,
            output_lines: output_lines.length,
            output_bytes: output_content.bytesize,
            last_line_partial: false,
            first_line_exceeds_limit: false,
            max_lines: max_lines,
            max_bytes: max_bytes
          )
        end

        # Truncate from the end of content.
        # @param content [String]
        # @param max_lines [Integer]
        # @param max_bytes [Integer]
        # @return [TruncationResult]
        # 方法功能：从内容尾部进行截断
        # 参数：content - 内容字符串，max_lines - 最大行数，max_bytes - 最大字节数
        # 返回值：TruncationResult 结构体实例
        def self.truncate_tail(content, max_lines: DEFAULT_MAX_LINES, max_bytes: DEFAULT_MAX_BYTES)
          total_bytes = content.bytesize
          lines = split_lines_for_counting(content)
          total_lines = lines.length

          if total_lines <= max_lines && total_bytes <= max_bytes
            return TruncationResult.new(
              content: content,
              truncated: false,
              truncated_by: nil,
              total_lines: total_lines,
              total_bytes: total_bytes,
              output_lines: total_lines,
              output_bytes: total_bytes,
              last_line_partial: false,
              first_line_exceeds_limit: false,
              max_lines: max_lines,
              max_bytes: max_bytes
            )
          end

          output_lines = []
          output_bytes = 0
          truncated_by = 'lines'
          last_line_partial = false

          (lines.length - 1).downto(0) do |index|
            break if output_lines.length >= max_lines

            line = lines[index] || ''
            line_bytes = line.bytesize + (output_lines.length.positive? ? 1 : 0)

            if output_bytes + line_bytes > max_bytes
              truncated_by = 'bytes'
              if output_lines.empty?
                partial = truncate_string_to_bytes_from_end(line, max_bytes)
                output_lines.unshift(partial)
                output_bytes = partial.bytesize
                last_line_partial = true
              end
              break
            end

            output_lines.unshift(line)
            output_bytes += line_bytes
          end

          output_content = output_lines.join("\n")
          TruncationResult.new(
            content: output_content,
            truncated: true,
            truncated_by: truncated_by,
            total_lines: total_lines,
            total_bytes: total_bytes,
            output_lines: output_lines.length,
            output_bytes: output_content.bytesize,
            last_line_partial: last_line_partial,
            first_line_exceeds_limit: false,
            max_lines: max_lines,
            max_bytes: max_bytes
          )
        end

        class << self
          private

          # Split content into lines for counting.
          # @param content [String]
          # @return [Array<String>]
          # 方法功能：将内容分割为行用于计数
          # 参数：content - 内容字符串
          # 返回值：行数组
          def split_lines_for_counting(content)
            return [] if content.empty?

            lines = content.split("\n")
            lines.pop if content.end_with?("\n")
            lines
          end

          # Truncate string to max bytes from end.
          # @param text [String]
          # @param max_bytes [Integer]
          # @return [String]
          # 方法功能：从尾部截断字符串到指定字节数
          # 参数：text - 文本字符串，max_bytes - 最大字节数
          # 返回值：截断后的字符串
          def truncate_string_to_bytes_from_end(text, max_bytes)
            buffer = text.encode('UTF-8')
            return text if buffer.bytesize <= max_bytes

            start = buffer.bytesize - max_bytes
            # Ensure we don't split a multi-byte character
            start += 1 while start < buffer.bytesize && (buffer.bytes[start] & 0xc0) == 0x80

            buffer.byteslice(start..).encode('UTF-8')
          end
        end
      end
    end
  end
end
