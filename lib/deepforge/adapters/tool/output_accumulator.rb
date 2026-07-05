# frozen_string_literal: true

# 文件用途：输出累积器
# 使用方法：通过 OutputAccumulator 类累积工具输出，支持截断和临时文件

require 'tempfile'
require_relative 'truncate'

module DeepForge
  module Adapters
    module Tool
      # 输出累积器快照结构体
      OutputAccumulatorSnapshot = Struct.new(:content, :truncation, :full_output_path, keyword_init: true)

      # 输出累积器选项结构体
      OutputAccumulatorOptions = Struct.new(:max_lines, :max_bytes, :temp_file_prefix, keyword_init: true)

      # 类功能：累积工具输出，支持截断和临时文件存储
      class OutputAccumulator
        # 方法功能：初始化输出累积器
        # 参数：options - OutputAccumulatorOptions 结构体实例
        def initialize(options)
          @max_lines = options.max_lines
          @max_bytes = options.max_bytes
          @max_rolling_bytes = [@max_bytes * 2, 1].max
          @temp_file_prefix = options.temp_file_prefix

          @raw_chunks = []
          @tail_text = ''
          @tail_bytes = 0
          @tail_starts_at_line_boundary = true
          @total_raw_bytes = 0
          @total_decoded_bytes = 0
          @completed_lines = 0
          @total_lines = 0
          @current_line_bytes = 0
          @has_open_line = false
          @finished = false

          @temp_file_path = nil
          @temp_file = nil
        end

        # Append data to the accumulator.
        # @param data [String]
        # @raise [RuntimeError] if already finished
        # 方法功能：向累积器追加数据
        # 参数：data - 数据字符串
        # 异常：如果已完成则抛出异常
        def append(data)
          raise 'Cannot append to a finished output accumulator' if @finished

          @total_raw_bytes += data.bytesize
          append_decoded_text(data)

          if @temp_file || should_use_temp_file?
            ensure_temp_file
            @temp_file&.write(data)
          elsif data.bytesize.positive?
            @raw_chunks << data
          end
        end

        # Finish accumulating data.
        # 方法功能：完成数据累积
        def finish
          return if @finished

          @finished = true
          ensure_temp_file if should_use_temp_file?
        end

        # Take a snapshot of the current output.
        # @param persist_if_truncated [Boolean]
        # @return [OutputAccumulatorSnapshot]
        # 方法功能：获取当前输出的快照
        # 参数：persist_if_truncated - 如果截断是否持久化（可选）
        # 返回值：OutputAccumulatorSnapshot 结构体实例
        def snapshot(persist_if_truncated: false)
          tail_truncation = Truncate.truncate_tail(get_snapshot_text, max_lines: @max_lines, max_bytes: @max_bytes)
          truncated = @total_lines > @max_lines || @total_decoded_bytes > @max_bytes

          truncation = tail_truncation.dup
          truncation[:truncated] = truncated
          if truncated
            truncation[:truncated_by] =
              tail_truncation[:truncated_by] || (@total_decoded_bytes > @max_bytes ? 'bytes' : 'lines')
          else
            truncation[:truncated_by] = nil
          end
          truncation[:total_lines] = @total_lines
          truncation[:total_bytes] = @total_decoded_bytes
          truncation[:max_lines] = @max_lines
          truncation[:max_bytes] = @max_bytes

          ensure_temp_file if persist_if_truncated && truncated

          OutputAccumulatorSnapshot.new(
            content: truncation[:content],
            truncation: truncation,
            full_output_path: @temp_file_path
          )
        end

        # Close the temp file if open.
        # 方法功能：关闭临时文件
        def close_temp_file
          return unless @temp_file

          @temp_file.close
          @temp_file = nil
        end

        # Get the byte length of the last line.
        # @return [Integer]
        # 方法功能：获取最后一行的字节长度
        # 返回值：字节数
        def last_line_bytes
          @current_line_bytes
        end

        private

        # Append decoded text and update line counts.
        # @param text [String]
        # 方法功能：追加解码后的文本并更新行计数
        # 参数：text - 文本字符串
        def append_decoded_text(text)
          return if text.empty?

          bytes = text.bytesize
          @total_decoded_bytes += bytes
          @tail_text += text
          @tail_bytes += bytes
          trim_tail if @tail_bytes > @max_rolling_bytes * 2

          newlines = text.count("\n")
          last_newline = text.rindex("\n")

          if newlines.zero?
            @current_line_bytes += bytes
            @has_open_line = true
          else
            @completed_lines += newlines
            tail = last_newline ? text[(last_newline + 1)..] : ''
            @current_line_bytes = tail.bytesize
            @has_open_line = !tail.empty?
          end

          @total_lines = @completed_lines + (@has_open_line ? 1 : 0)
        end

        # Trim the tail buffer.
        # 方法功能：修剪尾部缓冲区
        def trim_tail
          buffer = @tail_text.encode('UTF-8')
          if buffer.bytesize <= @max_rolling_bytes
            @tail_bytes = buffer.bytesize
            return
          end

          start = buffer.bytesize - @max_rolling_bytes
          # Ensure we don't split a multi-byte character
          start += 1 while start < buffer.bytesize && (buffer.bytes[start] & 0xc0) == 0x80

          @tail_starts_at_line_boundary = start.zero? ? @tail_starts_at_line_boundary : buffer.bytes[start - 1] == 0x0a
          @tail_text = buffer.byteslice(start..).encode('UTF-8')
          @tail_bytes = @tail_text.bytesize
        end

        # Get text for snapshot.
        # @return [String]
        # 方法功能：获取快照文本
        # 返回值：文本字符串
        def get_snapshot_text
          if @tail_starts_at_line_boundary
            @tail_text
          else
            first_newline = @tail_text.index("\n")
            first_newline ? @tail_text[(first_newline + 1)..] : @tail_text
          end
        end

        # Check if temp file should be used.
        # @return [Boolean]
        # 方法功能：检查是否应该使用临时文件
        # 返回值：布尔值
        def should_use_temp_file?
          @total_raw_bytes > @max_bytes ||
            @total_decoded_bytes > @max_bytes ||
            @total_lines > @max_lines
        end

        # Ensure temp file exists and write buffered chunks.
        # 方法功能：确保临时文件存在并写入缓冲区
        def ensure_temp_file
          return if @temp_file_path

          @temp_file_path = default_temp_file_path
          @temp_file = File.open(@temp_file_path, 'w')
          @raw_chunks.each { |chunk| @temp_file.write(chunk) }
          @raw_chunks = []
        end

        # Generate a temp file path.
        # @return [String]
        # 方法功能：生成临时文件路径
        # 返回值：临时文件路径字符串
        def default_temp_file_path
          id = SecureRandom.hex(8)
          File.join(Dir.tmpdir, "#{@temp_file_prefix}-#{id}.log")
        end
      end
    end
  end
end
