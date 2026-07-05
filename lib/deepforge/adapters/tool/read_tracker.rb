# frozen_string_literal: true

# 文件用途：读取追踪器
# 使用方法：通过 ReadTracker 类追踪文件读取，实现编辑前必须先读取的守卫机制

require 'pathname'

module DeepForge
  module Adapters
    module Tool
      # ReadTracker 选项结构体
      ReadTrackerOptions = Struct.new(:enabled, :require_old_text_in_read, keyword_init: true)

      # 读取记录结构体，追踪文件读取状态
      ReadRecord = Struct.new(:absolute_path, :relative_path, :content, :truncated, :turn_id, keyword_init: true)

      # 类功能：读取前编辑守卫，确保在编辑文件前已读取该文件
      class ReadTracker
        # 方法功能：初始化读取追踪器
        # 参数：options - ReadTrackerOptions 结构体实例
        def initialize(options)
          @options = options
          @records = {} # thread_id => { absolute_path => ReadRecord }
        end

        # Observe a tool result from a read operation.
        # @param context [ToolHostContext]
        # @param call [ToolCallLike]
        # @param output [Object]
        # @param is_error [Boolean]
        # 方法功能：观察工具结果并记录读取操作
        # 参数：context - 上下文，call - 调用信息，output - 输出，is_error - 是否错误
        def observe_tool_result(context:, call:, output:, is_error: false)
          return unless @options.enabled
          return if is_error || call.tool_name != 'read'
          return unless output.is_a?(Hash)

          raw_path = output[:path].to_s
          return if raw_path.empty?

          absolute_path = normalize_path(raw_path, context.workspace)
          record = ReadRecord.new(
            absolute_path: absolute_path,
            truncated: output[:truncated] == true,
            turn_id: context.turn_id,
            relative_path: output[:relative_path]&.to_s,
            content: output[:content]&.to_s
          )

          thread_records = @records[context.thread_id] || {}
          thread_records[absolute_path] = record
          @records[context.thread_id] = thread_records
        end

        # Validate that a file has been read before editing.
        # @param context [ToolHostContext]
        # @param call [ToolCallLike]
        # @return [Hash] with :ok (boolean) and optionally :message
        # 方法功能：在编辑前验证文件是否已读取
        # 参数：context - 上下文，call - 调用信息
        # 返回值：包含 :ok 和可选 :message 的哈希
        def validate_before_tool(context:, call:)
          return { ok: true } unless @options.enabled
          return { ok: true } unless edit_tool?(call)

          raw_path = call.arguments[:path].to_s
          return { ok: true } if raw_path.strip.empty?

          absolute_path = normalize_path(raw_path, context.workspace)
          record = @records[context.thread_id]&.fetch(absolute_path, nil)

          unless record
            return {
              ok: false,
              message: "read-before-edit guard blocked edit for #{display_path(raw_path, context.workspace)}. " \
                       'Read the current file contents in this turn before editing so SEARCH text is based on fresh bytes.'
            }
          end

          if record.turn_id != context.turn_id
            return {
              ok: false,
              message: "read-before-edit guard blocked edit for #{display_path(raw_path, context.workspace)}. " \
                       'The previous read is from an earlier turn; read the file again before editing.'
            }
          end

          return { ok: true } unless @options.require_old_text_in_read

          missing = old_text_fragments(call.arguments).select do |fragment|
            next false if fragment.strip.empty?

            record.content.nil? || !record.content.include?(fragment)
          end

          if missing.empty?
            { ok: true }
          else
            display = record.relative_path || display_path(raw_path, context.workspace)
            {
              ok: false,
              message: "read-before-edit guard blocked edit for #{display}. " \
                       'At least one oldText fragment was not present in the latest read output; read a narrower range that includes the exact text before editing.'
            }
          end
        end

        # Clear records for a thread.
        # @param thread_id [String, nil]
        # 方法功能：清除指定线程的记录
        # 参数：thread_id - 线程 ID（可选）
        def clear(thread_id = nil)
          if thread_id
            @records.delete(thread_id)
          else
            @records.clear
          end
        end

        class << self
          # 方法功能：规范化读取追踪器选项
          def normalize_read_tracker_options(input)
            case input
            when true
              ReadTrackerOptions.new(enabled: true, require_old_text_in_read: true)
            when false, nil
              ReadTrackerOptions.new(enabled: false, require_old_text_in_read: true)
            when ReadTrackerOptions
              ReadTrackerOptions.new(
                enabled: input.enabled == true,
                require_old_text_in_read: input.require_old_text_in_read != false
              )
            else
              ReadTrackerOptions.new(enabled: false, require_old_text_in_read: true)
            end
          end
        end

        private

        # Check if a call is an edit tool.
        # @param call [ToolCallLike]
        # @return [Boolean]
        # 方法功能：检查调用是否为编辑工具
        # 参数：call - 调用信息
        # 返回值：布尔值
        def edit_tool?(call)
          %w[edit edit_file apply_patch].include?(call.tool_name)
        end

        # Extract old text fragments from arguments.
        # @param args [Hash]
        # @return [Array<String>]
        # 方法功能：从参数中提取旧文本片段
        # 参数：args - 参数哈希
        # 返回值：字符串数组
        def old_text_fragments(args)
          out = []
          out << args[:old_text] if args[:old_text].is_a?(String)

          if args[:edits].is_a?(Array)
            args[:edits].each do |edit|
              out << edit[:old_text] if edit.is_a?(Hash) && edit[:old_text].is_a?(String)
            end
          end

          out
        end

        # Normalize a path to absolute.
        # @param path [String]
        # @param workspace [String]
        # @return [String]
        # 方法功能：将路径规范化为绝对路径
        # 参数：path - 路径字符串，workspace - 工作区路径
        # 返回值：绝对路径字符串
        def normalize_path(path, workspace)
          if File.absolute_path?(path)
            File.expand_path(path)
          else
            File.expand_path(path, workspace || '.')
          end
        end

        # Display a path relative to workspace.
        # @param path [String]
        # @param workspace [String]
        # @return [String]
        # 方法功能：显示相对于工作区的路径
        # 参数：path - 路径字符串，workspace - 工作区路径
        # 返回值：相对路径或绝对路径字符串
        def display_path(path, workspace)
          absolute_path = normalize_path(path, workspace)
          rel = workspace ? Pathname.new(absolute_path).relative_path_from(Pathname.new(File.expand_path(workspace))).to_s : ''
          rel && !rel.start_with?('..') ? rel : absolute_path
        end
      end
    end
  end
end
