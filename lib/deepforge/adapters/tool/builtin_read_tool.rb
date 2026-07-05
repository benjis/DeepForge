# frozen_string_literal: true

# 文件用途：内置文件读取工具的完整实现
# 使用方法：通过 create 方法创建 read 工具定义，支持读取文本文件和图片文件

require 'fileutils'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供内置的文件读取工具
      # 支持文本文件读取、图片检测与缩放、输出截断等功能
      module BuiltinReadTool
        # 默认输出最大行数
        DEFAULT_MAX_LINES = 2000
        # 默认输出最大字节数
        DEFAULT_MAX_BYTES = 512_000

        # 读取操作结构体，包含 stat、read_file、detect_image_mime_type、resize_image 函数
        ReadOperations = Struct.new(:stat, :read_file, :detect_image_mime_type, :resize_image, keyword_init: true)
        # 读取工具选项结构体
        ReadToolOptions = Struct.new(:max_lines, :max_bytes, :auto_resize_images, :operations, keyword_init: true)
        # 缩放后的图片结果结构体
        ResizedImageResult = Struct.new(:data_base64, :mime_type, :width, :height, :original_width, :original_height,
                                        :was_resized, keyword_init: true)
        # 图片缩放选项结构体
        ResizeImageOptions = Struct.new(:max_width, :max_height, :max_bytes, keyword_init: true)

        # 文本切片结构体，用于描述截断后的输出信息
        TextSlice = Struct.new(
          :text, :truncated, :total_lines, :shown_lines,
          :total_bytes, :shown_bytes, :first_line_exceeds_limit,
          :truncated_by, :last_line_partial,
          keyword_init: true
        )

        # 方法功能：创建文件读取工具
        # 参数：options - 读取工具选项（可选）
        # 返回值：包含工具定义的哈希
        def self.create(options = {})
          options ||= ReadToolOptions.new
          options.operations&.stat || default_operations.stat
          options.operations&.read_file || default_operations.read_file
          options.operations&.detect_image_mime_type || default_operations.detect_image_mime_type
          options.operations&.resize_image
          options.auto_resize_images.nil? || options.auto_resize_images

          {
            name: 'read',
            description: 'Read a file from the workspace. Supports optional line offset and limit for large files.',
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                offset: { type: 'number' },
                limit: { type: 'number' }
              },
              required: ['path'],
              additional_properties: false
            },
            policy: 'auto',
            execute: ->(args, context) { execute_read(args, context, options) }
          }
        end

        # 方法功能：获取默认的读取操作
        # 返回值：ReadOperations 结构体实例
        def self.default_operations
          ReadOperations.new(
            stat: ->(path) { ::File.stat(path) },
            read_file: ->(path) { ::File.binread(path) },
            detect_image_mime_type: ->(buffer) { detect_image(buffer) },
            resize_image: nil
          )
        end

        # 方法功能：执行文件读取操作
        # 参数：args - 参数哈希，context - 上下文，options - 读取选项
        # 返回值：包含文件内容的哈希
        def self.execute_read(args, context, options)
          raw_path = args[:path].to_s.strip
          return error_output('path is required') if raw_path.empty?

          absolute_path = resolve_workspace_path(raw_path, context)
          relative_path = make_relative(absolute_path, context)

          begin
            file_buffer = ::File.binread(absolute_path)
          rescue StandardError => e
            return error_output("failed to read file: #{e.message}")
          end

          image = detect_image(file_buffer)
          return handle_image(image, file_buffer, absolute_path, relative_path, options, context) if image

          return error_output('read only supports text files in DeepForge serve mode') if binary_buffer?(file_buffer)

          text = file_buffer.encode('UTF-8', invalid: :replace, undef: :replace).gsub("\r\n", "\n")
          all_lines = text.split("\n")

          offset = [1, normalize_positive_integer(args[:offset], 1)].max
          effective_max_lines = options&.max_lines || DEFAULT_MAX_LINES
          effective_max_bytes = options&.max_bytes || DEFAULT_MAX_BYTES
          limit = normalize_positive_integer(args[:limit], effective_max_lines)

          selected = all_lines[(offset - 1)...(offset - 1 + limit)]&.join("\n") || ''
          truncated_result = truncate_head(selected, effective_max_lines, effective_max_bytes)

          truncated = TextSlice.new(
            text: truncated_result[:content],
            truncated: truncated_result[:truncated],
            total_lines: truncated_result[:total_lines],
            shown_lines: truncated_result[:output_lines],
            total_bytes: truncated_result[:total_bytes],
            shown_bytes: truncated_result[:output_bytes],
            first_line_exceeds_limit: truncated_result[:first_line_exceeds_limit],
            truncated_by: truncated_result[:truncated_by],
            last_line_partial: truncated_result[:last_line_partial]
          )

          content = truncated.text
          if truncated.first_line_exceeds_limit
            content = "[first line exceeds #{format_size(effective_max_bytes)} at line #{offset}. Use bash for a byte-limited slice of this line.]"
          elsif truncated.truncated
            end_line = [offset, offset + truncated.shown_lines - 1].max
            next_offset = end_line + 1
            if truncated.truncated_by == 'lines'
              content = "#{truncated.text}\n\n[showing lines #{offset}-#{end_line} of #{all_lines.length}. Use offset=#{next_offset} to continue.]"
            else
              content = "#{truncated.text}\n\n[showing lines #{offset}-#{end_line} of #{all_lines.length} (#{format_size(effective_max_bytes)} limit). Use offset=#{next_offset} to continue.]"
            end
          elsif offset - 1 + limit < all_lines.length
            next_offset = offset + limit
            remaining = all_lines.length - (offset - 1 + limit)
            content = "#{truncated.text}\n\n[#{remaining} more lines in file. Use offset=#{next_offset} to continue.]"
          end

          {
            output: {
              path: absolute_path,
              relative_path: relative_path,
              content: content,
              classification: nil,
              start_line: offset,
              end_line: [offset, offset + truncated.shown_lines - 1].max,
              total_lines: all_lines.length,
              truncated: truncated.truncated,
              truncation_by: truncated.truncated_by,
              first_line_exceeds_limit: truncated.first_line_exceeds_limit == true
            }
          }
        end

        # 方法功能：处理图片文件读取
        # 参数：image - 图片检测信息，file_buffer - 文件内容，absolute_path - 绝对路径，relative_path - 相对路径，options - 选项，context - 上下文
        # 返回值：包含图片信息的哈希
        def self.handle_image(image, file_buffer, absolute_path, relative_path, options, _context)
          if options&.auto_resize_images && options&.operations&.resize_image
            resized = options.operations.resize_image.call(file_buffer, image[:mime_type])
            if resized
              dimension_note = format_dimension_note(resized)
              return {
                output: {
                  path: absolute_path,
                  relative_path: relative_path,
                  kind: 'image',
                  mime_type: resized.mime_type,
                  width: resized.width,
                  height: resized.height,
                  byte_size: file_buffer.bytesize,
                  data_base64: resized.data_base64,
                  note: dimension_note ? "Read image file [#{resized.mime_type}]\n#{dimension_note}" : "Read image file [#{resized.mime_type}]",
                  classification: nil,
                  resized: resized.was_resized == true
                }
              }
            end
          end

          {
            output: {
              path: absolute_path,
              relative_path: relative_path,
              kind: 'image',
              mime_type: image[:mime_type],
              width: image[:width],
              height: image[:height],
              byte_size: file_buffer.bytesize,
              data_base64: [file_buffer].pack('m0'),
              note: "Read image file [#{image[:mime_type]}]",
              classification: nil
            }
          }
        end

        # 方法功能：检测缓冲区是否为图片文件
        # 参数：buffer - 文件内容缓冲区
        # 返回值：包含 MIME 类型和尺寸的信息哈希或 nil
        def self.detect_image(buffer)
          return nil if buffer.bytesize < 8

          png_sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack('C*')
          if buffer.byteslice(0, 8) == png_sig
            width = buffer.byteslice(16, 4)&.unpack1('N')
            height = buffer.byteslice(20, 4)&.unpack1('N')
            { mime_type: 'image/png', width: width, height: height }
          elsif buffer.byteslice(0, 2).b == "\xFF\xD8".b
            { mime_type: 'image/jpeg', width: nil, height: nil }
          elsif buffer.byteslice(0, 4) == 'GIF8'
            width = buffer.byteslice(6, 2)&.unpack1('v')
            height = buffer.byteslice(8, 2)&.unpack1('v')
            { mime_type: 'image/gif', width: width, height: height }
          elsif buffer.byteslice(0, 4) == 'RIFF' && buffer.byteslice(8, 4) == 'WEBP'
            { mime_type: 'image/webp', width: nil, height: nil }
          end
        end

        # 方法功能：检测缓冲区是否为二进制内容
        # 参数：buffer - 文件内容缓冲区
        # 返回值：布尔值
        def self.binary_buffer?(buffer)
          sample = buffer.byteslice(0, [8192, buffer.bytesize].min)
          sample.include?("\x00")
        end

        # 方法功能：从头部截断文本
        # 参数：text - 原始文本，max_lines - 最大行数，max_bytes - 最大字节数
        # 返回值：截断结果哈希
        def self.truncate_head(text, max_lines, max_bytes)
          lines = text.split("\n")
          total_lines = lines.length
          total_bytes = text.bytesize

          if total_lines > max_lines || total_bytes > max_bytes
            truncated_lines = lines.last(max_lines)
            truncated_text = truncated_lines.join("\n")

            truncated_text = truncated_text.byteslice(0, max_bytes) if truncated_text.bytesize > max_bytes

            {
              content: truncated_text,
              truncated: true,
              total_lines: total_lines,
              output_lines: truncated_lines.length,
              total_bytes: total_bytes,
              output_bytes: truncated_text.bytesize,
              first_line_exceeds_limit: false,
              truncated_by: total_lines > max_lines ? 'lines' : 'bytes',
              last_line_partial: !text.end_with?("\n")
            }
          else
            {
              content: text,
              truncated: false,
              total_lines: total_lines,
              output_lines: total_lines,
              total_bytes: total_bytes,
              output_bytes: total_bytes,
              first_line_exceeds_limit: false,
              truncated_by: nil,
              last_line_partial: false
            }
          end
        end

        # 方法功能：将路径解析为工作区内的绝对路径
        # 参数：raw_path - 原始路径，context - 上下文
        # 返回值：绝对路径字符串
        def self.resolve_workspace_path(raw_path, context)
          workspace = context[:workspace] || Dir.pwd
          if ::File.absolute_path?(raw_path)
            raw_path
          else
            ::File.join(workspace, raw_path)
          end
        end

        # 方法功能：将绝对路径转换为相对路径
        # 参数：absolute_path - 绝对路径，context - 上下文
        # 返回值：相对路径字符串
        def self.make_relative(absolute_path, context)
          workspace = context[:workspace] || Dir.pwd
          begin
            Pathname.new(absolute_path).relative_path_from(Pathname.new(workspace)).to_s
          rescue ArgumentError
            absolute_path
          end
        end

        # 方法功能：将值规范化为正整数
        # 参数：value - 输入值，default - 默认值
        # 返回值：正整数或默认值
        def self.normalize_positive_integer(value, default)
          return default if value.nil?

          int_val = value.to_i
          int_val.positive? ? int_val : default
        end

        # 方法功能：将字节数格式化为人类可读的字符串
        # 参数：bytes - 字节数
        # 返回值：格式化后的字符串
        def self.format_size(bytes)
          return "#{bytes} B" if bytes < 1024
          return "#{(bytes / 1024.0).round(1)} KB" if bytes < 1024 * 1024

          "#{(bytes / (1024.0 * 1024)).round(1)} MB"
        end

        # 方法功能：生成图片尺寸说明文本
        # 参数：resized - ResizedImageResult 结构体
        # 返回值：尺寸说明字符串或 nil
        def self.format_dimension_note(resized)
          return nil unless resized.was_resized

          "Resized to #{resized.width}x#{resized.height} from #{resized.original_width}x#{resized.original_height}"
        end

        # 方法功能：生成错误输出格式
        # 参数：message - 错误消息
        # 返回值：包含错误信息的哈希
        def self.error_output(message)
          {
            output: { error: message },
            is_error: true
          }
        end
      end
    end
  end
end
