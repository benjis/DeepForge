# frozen_string_literal: true

# 文件用途：内置文件操作工具（写入和编辑）
# 使用方法：通过 create_write_tool 或 create_edit_tool 创建文件操作工具

require 'fileutils'
require 'diff/lcs'
require 'diff/lcs/hunk'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供文件写入和编辑的内置工具实现
      module BuiltinFileTools
        # 写入工具选项结构体
        WriteLocalToolOptions = Struct.new(:operations, keyword_init: true)
        # 编辑工具选项结构体
        EditLocalToolOptions = Struct.new(:operations, keyword_init: true)
        # 写入工具操作结构体，包含 mkdir 和 write_file 函数
        WriteLocalToolOperations = Struct.new(:mkdir, :write_file, keyword_init: true)
        # 编辑工具操作结构体，包含 read_file 和 write_file 函数
        EditLocalToolOperations = Struct.new(:read_file, :write_file, keyword_init: true)

        # 方法功能：创建文件写入工具
        # 参数：options - 写入工具选项（可选）
        # 返回值：包含工具定义的哈希
        def self.create_write_tool(options = {})
          options ||= WriteLocalToolOptions.new
          mkdir_op = options.operations&.mkdir || default_write_operations.mkdir
          write_file_op = options.operations&.write_file || default_write_operations.write_file

          {
            name: 'write',
            description: 'Create or overwrite a workspace file with the provided content.',
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                content: { type: 'string' }
              },
              required: %w[path content],
              additional_properties: false
            },
            policy: 'on-request',
            tool_kind: 'file_change',
            execute: ->(args, context) { execute_write(args, context, mkdir_op, write_file_op) }
          }
        end

        # 方法功能：创建文件编辑工具
        # 参数：options - 编辑工具选项（可选）
        # 返回值：包含工具定义的哈希
        def self.create_edit_tool(options = {})
          options ||= EditLocalToolOptions.new
          read_file_op = options.operations&.read_file || default_edit_operations.read_file
          write_file_op = options.operations&.write_file || default_edit_operations.write_file

          {
            name: 'edit',
            description: 'Edit a workspace file using exact text replacement. Supports multiple disjoint edits in one call.',
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                old_text: { type: 'string' },
                new_text: { type: 'string' },
                edits: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      old_text: { type: 'string' },
                      new_text: { type: 'string' }
                    },
                    required: %w[old_text new_text],
                    additional_properties: false
                  }
                }
              },
              required: ['path'],
              additional_properties: false
            },
            policy: 'on-request',
            tool_kind: 'file_change',
            execute: ->(args, context) { execute_edit(args, context, read_file_op, write_file_op) }
          }
        end

        # 方法功能：获取默认的写入操作
        # 返回值：WriteLocalToolOperations 结构体实例
        def self.default_write_operations
          WriteLocalToolOperations.new(
            mkdir: ->(path) { FileUtils.mkdir_p(path) },
            write_file: ->(path, content) { File.write(path, content) }
          )
        end

        # 方法功能：获取默认的编辑操作
        # 返回值：EditLocalToolOperations 结构体实例
        def self.default_edit_operations
          EditLocalToolOperations.new(
            read_file: ->(path) { File.read(path) },
            write_file: ->(path, content) { File.write(path, content) }
          )
        end

        # 方法功能：执行文件写入操作
        # 参数：args - 参数哈希，context - 上下文，mkdir_op - 创建目录函数，write_file_op - 写入文件函数
        # 返回值：包含写入结果的哈希
        def self.execute_write(args, context, mkdir_op, write_file_op)
          raw_path = args[:path].to_s.strip
          content = args[:content]

          return error_output('path and content are required') if raw_path.empty? || content.nil?

          absolute_path = resolve_workspace_path(raw_path, context)
          relative_path = make_relative(absolute_path, context)

          begin
            mkdir_op.call(File.dirname(absolute_path))
            write_file_op.call(absolute_path, content)
            {
              output: {
                path: absolute_path,
                relative_path: relative_path,
                bytes_written: content.bytesize
              }
            }
          rescue StandardError => e
            error_output("failed to write file: #{e.message}")
          end
        end

        # 方法功能：执行文件编辑操作
        # 参数：args - 参数哈希，context - 上下文，read_file_op - 读取文件函数，write_file_op - 写入文件函数
        # 返回值：包含编辑结果和差异的哈希
        def self.execute_edit(args, context, read_file_op, write_file_op)
          raw_path = args[:path].to_s.strip
          edits = parse_edit_instructions(args)

          return error_output('path and at least one edit are required') if raw_path.empty? || edits.empty?

          absolute_path = resolve_workspace_path(raw_path, context)
          relative_path = make_relative(absolute_path, context)

          begin
            raw_source = read_file_op.call(absolute_path)
            bom = raw_source.start_with?("\xEF\xBB\xBF") ? "\xEF\xBB\xBF" : ''
            source = raw_source.sub(/\A\xEF\xBB\xBF/, '')

            line_ending = detect_line_ending(source)
            normalized_source = source.gsub("\r\n", "\n")

            new_content = apply_edits(normalized_source, edits, relative_path)
            restored = restore_line_endings(new_content, line_ending)
            next_content = bom + restored

            write_file_op.call(absolute_path, next_content)

            diff = generate_display_diff(normalized_source, new_content)
            patch = generate_unified_patch(relative_path, normalized_source, new_content)

            {
              output: {
                path: absolute_path,
                relative_path: relative_path,
                replacements: edits.length,
                bytes_written: next_content.bytesize,
                diff: diff,
                patch: patch,
                first_changed_line: first_changed_line(normalized_source, new_content)
              }
            }
          rescue StandardError => e
            error_output("failed to edit file: #{e.message}")
          end
        end

        # 方法功能：解析编辑指令参数
        # 参数：args - 参数哈希
        # 返回值：编辑指令数组
        def self.parse_edit_instructions(args)
          edits = []

          edits << { old_text: args[:old_text], new_text: args[:new_text] } if args[:old_text] && args[:new_text]

          if args[:edits].is_a?(Array)
            args[:edits].each do |edit|
              edits << { old_text: edit[:old_text], new_text: edit[:new_text] } if edit[:old_text] && edit[:new_text]
            end
          end

          edits
        end

        # 方法功能：应用编辑指令到源代码
        # 参数：source - 源代码字符串，edits - 编辑指令数组，_relative_path - 相对路径（未使用）
        # 返回值：编辑后的源代码字符串
        def self.apply_edits(source, edits, _relative_path)
          result = source.dup
          edits.each do |edit|
            old_text = edit[:old_text]
            new_text = edit[:new_text]
            raise "edit text not found in file: #{old_text[0..50]}..." unless result.include?(old_text)

            result = result.sub(old_text, new_text)
          end
          result
        end

        # 方法功能：检测文本的换行符风格
        # 参数：text - 文本内容
        # 返回值：换行符字符串
        def self.detect_line_ending(text)
          return "\r\n" if text.include?("\r\n")
          return "\r" if text.include?("\r") && !text.include?("\n")

          "\n"
        end

        # 方法功能：恢复文本的换行符风格
        # 参数：text - 文本内容，line_ending - 目标换行符
        # 返回值：恢复换行符后的文本
        def self.restore_line_endings(text, line_ending)
          return text if line_ending == "\n"

          text.gsub("\n", line_ending)
        end

        # 方法功能：生成显示用的差异文本
        # 参数：old_text - 旧文本，new_text - 新文本
        # 返回值：差异文本字符串
        def self.generate_display_diff(old_text, new_text)
          old_lines = old_text.split("\n", -1)
          new_lines = new_text.split("\n", -1)

          diffs = []
          Diff::LCS.sdiff(old_lines, new_lines) do |change|
            case change
            when Diff::LCS::Change
              case change.action
              when '-'
                diffs << "- #{change.old_element}"
              when '+'
                diffs << "+ #{change.new_element}"
              when '!'
                diffs << "- #{change.old_element}"
                diffs << "+ #{change.new_element}"
              end
            end
          end

          diffs.join("\n")
        end

        # 方法功能：生成统一补丁格式的差异
        # 参数：relative_path - 相对路径，old_text - 旧文本，new_text - 新文本
        # 返回值：统一补丁字符串
        def self.generate_unified_patch(relative_path, old_text, new_text)
          old_lines = old_text.split("\n", -1)
          new_lines = new_text.split("\n", -1)

          diffs = Diff::LCS.sdiff(old_lines, new_lines)
          return '' if diffs.empty?

          hunks = []
          current_hunk = nil

          diffs.each_with_index do |change, index|
            case change.action
            when '-'
              current_hunk ||= { start: index, lines: [] }
              current_hunk[:lines] << "- #{change.old_element}"
            when '+'
              current_hunk ||= { start: index, lines: [] }
              current_hunk[:lines] << "+ #{change.new_element}"
            when '!'
              current_hunk ||= { start: index, lines: [] }
              current_hunk[:lines] << "- #{change.old_element}"
              current_hunk[:lines] << "+ #{change.new_element}"
            else
              if current_hunk
                hunks << current_hunk
                current_hunk = nil
              end
            end
          end
          hunks << current_hunk if current_hunk

          header = "--- a/#{relative_path}\n+++ b/#{relative_path}"
          hunk_texts = hunks.map do |hunk|
            "@@ -#{hunk[:start] + 1},#{hunk[:lines].length} +#{hunk[:start] + 1},#{hunk[:lines].length} @@\n#{hunk[:lines].join("\n")}"
          end

          "#{header}\n#{hunk_texts.join("\n")}"
        end

        # 方法功能：查找第一个变更的行号
        # 参数：old_text - 旧文本，new_text - 新文本
        # 返回值：行号（从1开始）或 nil
        def self.first_changed_line(old_text, new_text)
          old_lines = old_text.split("\n")
          new_lines = new_text.split("\n")

          old_lines.each_with_index do |line, index|
            return index + 1 if line != new_lines[index]
          end

          nil
        end

        # 方法功能：将路径解析为工作区内的绝对路径
        # 参数：raw_path - 原始路径，context - 上下文
        # 返回值：绝对路径字符串
        def self.resolve_workspace_path(raw_path, context)
          workspace = context[:workspace] || Dir.pwd
          if File.absolute_path?(raw_path)
            raw_path
          else
            File.join(workspace, raw_path)
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
