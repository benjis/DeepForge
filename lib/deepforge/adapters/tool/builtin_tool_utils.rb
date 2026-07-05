# frozen_string_literal: true

# 文件用途：内置工具的通用工具函数集
# 使用方法：提供路径解析、二进制检测、图片识别、文本编辑等通用功能

require 'fileutils'
require 'open3'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：为内置工具提供通用的工具函数
      module BuiltinToolUtils
        # 方法功能：包装工具执行并捕获异常
        # 参数：无（通过 yield 传入要执行的代码块）
        # 返回值：包含 :output 和可选 :is_error 的哈希
        def self.with_tool_boundary
          yield
        rescue StandardError => e
          {
            output: { error: e.message },
            is_error: true
          }
        end

        # 方法功能：解析工作区根路径
        # 参数：workspace - 工作区路径
        # 返回值：绝对路径字符串
        def self.workspace_root(workspace)
          return Dir.pwd if workspace.nil? || workspace.strip.empty?

          File.absolute_path(workspace)
        end

        # 方法功能：解析相对于工作区的路径
        # 参数：input_path - 输入路径，context - 上下文
        # 返回值：包含 :workspace_root、:absolute_path、:relative_path 的哈希
        def self.resolve_workspace_path(input_path, context)
          root = workspace_root(context.workspace)
          absolute_path = File.absolute_path(input_path, root)
          relative_path = Pathname.new(absolute_path).relative_path_from(Pathname.new(root)).to_s

          if relative_path == '..' || relative_path.start_with?('../') || File.absolute_path?(relative_path)
            raise "path escapes the workspace root: #{input_path}"
          end

          {
            workspace_root: root,
            absolute_path: absolute_path,
            relative_path: relative_path.empty? ? '.' : relative_path
          }
        end

        # 方法功能：检查缓冲区是否为二进制内容
        # 参数：buffer - 文件内容缓冲区
        # 返回值：布尔值
        def self.binary_buffer?(buffer)
          sample = buffer[0, [buffer.length, 4096].min]
          sample.include?("\x00".b)
        end

        # 方法功能：从缓冲区检测图片 MIME 类型
        # 参数：buffer - 文件内容缓冲区
        # 返回值：ImageDetection 结构体或 nil
        def self.detect_image_mime_type(buffer)
          # PNG
          if buffer.length >= 8 &&
             buffer[0] == 0x89 && buffer[1] == 0x50 &&
             buffer[2] == 0x4e && buffer[3] == 0x47 &&
             buffer[4] == 0x0d && buffer[5] == 0x0a &&
             buffer[6] == 0x1a && buffer[7] == 0x0a
            if buffer.length >= 24
              width = buffer[16..19].unpack1('N')
              height = buffer[20..23].unpack1('N')
              return ImageDetection.new(mime_type: 'image/png', width: width, height: height)
            end
            return ImageDetection.new(mime_type: 'image/png')
          end

          # JPEG
          if buffer.length >= 3 &&
             buffer[0] == 0xff && buffer[1] == 0xd8 && buffer[2] == 0xff
            offset = 2
            while offset + 9 < buffer.length
              break unless buffer[offset] == 0xff

              marker = buffer[offset + 1]
              size = buffer[(offset + 2)..(offset + 3)].unpack1('n')
              if marker.between?(0xc0, 0xc3) && size >= 7
                height = buffer[(offset + 5)..(offset + 6)].unpack1('n')
                width = buffer[(offset + 7)..(offset + 8)].unpack1('n')
                return ImageDetection.new(mime_type: 'image/jpeg', width: width, height: height)
              end
              offset += 2 + size
            end
            return ImageDetection.new(mime_type: 'image/jpeg')
          end

          # GIF
          if buffer.length >= 6
            header = buffer[0..5].unpack1('A6')
            if %w[GIF87a GIF89a].include?(header)
              if buffer.length >= 10
                width = buffer[6..7].unpack1('v')
                height = buffer[8..9].unpack1('v')
                return ImageDetection.new(mime_type: 'image/gif', width: width, height: height)
              end
              return ImageDetection.new(mime_type: 'image/gif')
            end
          end

          # WebP
          if buffer.length >= 12 &&
             buffer[0..3] == 'RIFF' && buffer[8..11] == 'WEBP'
            if buffer.length >= 30 && buffer[12..15] == 'VP8X'
              width = 1 + buffer[24..26].unpack1('V')
              height = 1 + buffer[27..29].unpack1('V')
              return ImageDetection.new(mime_type: 'image/webp', width: width, height: height)
            end
            return ImageDetection.new(mime_type: 'image/webp')
          end

          nil
        end

        # 方法功能：获取文件的读取分类
        # 参数：absolute_path - 绝对路径，workspace - 工作区路径
        # 返回值：ReadClassification 结构体或 nil
        def self.get_read_classification(absolute_path, workspace)
          file_name = File.basename(absolute_path)

          if file_name == 'SKILL.md'
            label = File.basename(File.dirname(absolute_path))
            label = file_name if label.empty?
            return ReadClassification.new(kind: 'skill', label: label)
          end

          if COMPACT_RESOURCE_FILE_NAMES.include?(file_name)
            rel = Pathname.new(absolute_path).relative_path_from(Pathname.new(workspace_root(workspace))).to_s
            return ReadClassification.new(kind: 'resource', label: rel.empty? ? file_name : rel)
          end

          relative_path = Pathname.new(absolute_path).relative_path_from(Pathname.new(workspace_root(workspace))).to_s
          if relative_path == 'README.md' || relative_path.start_with?('docs/') || relative_path.start_with?('examples/')
            return ReadClassification.new(kind: 'docs', label: relative_path)
          end

          nil
        end

        # 方法功能：为缩放后的图片生成尺寸说明
        # 参数：image - ResizedImageResult 结构体
        # 返回值：尺寸说明字符串或 nil
        def self.format_dimension_note(image)
          return nil unless image.was_resized && image.original_width && image.original_height

          scale = image.original_width.to_f / image.width
          "[Image: original #{image.original_width}x#{image.original_height}, displayed at #{image.width}x#{image.height}. Multiply coordinates by #{'%.2f' % scale} to map to original image.]"
        end

        # 方法功能：描述截断模式
        # 参数：mode - 模式字符串
        # 返回值：描述字符串
        def self.describe_kind(mode)
          mode == 'head' ? 'first' : 'last'
        end

        # 方法功能：获取 shell 配置
        # 返回值：ShellConfig 结构体实例
        def self.shell_config
          if RbConfig::CONFIG['host_os'].include?('mswin') || RbConfig::CONFIG['host_os'].include?('mingw')
            stdout, status = Open3.capture2('where', 'bash.exe')
            if status.success?
              candidate = stdout.split("\r\n").map(&:strip).find { |l| !l.empty? }
              return ShellConfig.new(shell: candidate, args: ['-lc']) if candidate
            end
            return ShellConfig.new(shell: 'sh', args: ['-lc'])
          end

          return ShellConfig.new(shell: '/bin/bash', args: ['-lc']) if File.exist?('/bin/bash')

          stdout, status = Open3.capture2('which', 'bash')
          candidate = stdout.strip if status.success?
          return ShellConfig.new(shell: candidate, args: ['-lc']) if candidate && !candidate.empty?

          ShellConfig.new(shell: 'sh', args: ['-lc'])
        end

        # 方法功能：从候选列表中解析可执行文件
        # 参数：candidates - 候选路径数组
        # 返回值：可执行文件路径或 nil
        def self.resolve_executable(candidates)
          candidates.each do |candidate|
            return candidate if candidate.include?('/') && File.exist?(candidate) && executable_responds?(candidate)

            next if candidate.include?('/')

            stdout, status = Open3.capture2('which', candidate)
            resolved = stdout.strip if status.success?
            return resolved if resolved && !resolved.empty? && executable_responds?(resolved)
          end
          nil
        end

        # 方法功能：创建进程并捕获输出
        # 参数：file - 可执行文件路径，args - 参数数组，cwd - 工作目录，signal - 信号（可选）
        # 返回值：包含 :stdout、:stderr、:exit_code 的哈希
        def self.spawn_capture(file, args, cwd:, signal: nil)
          stdout_str = ''
          stderr_str = ''

          Open3.popen3(file, *args, chdir: cwd) do |stdin, stdout, stderr, wait_thr|
            stdin.close

            stdout_thread = Thread.new { stdout_str = stdout.read }
            stderr_thread = Thread.new { stderr_str = stderr.read }

            stdout_thread.join
            stderr_thread.join

            exit_code = wait_thr.value.exitstatus
            { stdout: stdout_str, stderr: stderr_str, exit_code: exit_code }
          end
        end

        # 方法功能：递归收集路径
        # 参数：root - 根目录，include_directories - 是否包含目录，limit - 结果限制
        # 返回值：路径字符串数组
        def self.collect_paths(root, include_directories: false, limit: 1000)
          results = []
          queue = [root]

          while !queue.empty? && results.length < limit
            current = queue.shift
            break unless current

            entries = Dir.entries(current).sort
            entries.each do |name|
              next if ['.', '..'].include?(name)

              full_path = File.join(current, name)
              if File.directory?(full_path)
                results << full_path if include_directories
                queue << full_path
              else
                results << full_path
              end
              break if results.length >= limit
            end
          end

          results
        end

        # 方法功能：列出目录内容
        # 参数：target_path - 目标路径，root - 根目录，recursive - 是否递归，limit - 结果限制
        # 返回值：ListEntry 结构体数组
        def self.list_directory(target_path, root, recursive, limit)
          target_stat = File.lstat(target_path)
          return [make_list_entry(target_path, root, target_stat)] unless target_stat.directory?

          unless recursive
            entries = Dir.entries(target_path).sort.first(limit)
            return entries.filter_map do |name|
              next if ['.', '..'].include?(name)

              entry_path = File.join(target_path, name)
              make_list_entry(entry_path, root, File.lstat(entry_path))
            end
          end

          paths = collect_paths(target_path, include_directories: true, limit: limit)
          paths.filter_map { |path| make_list_entry(path, root, File.lstat(path)) }
        end

        # 方法功能：使用自定义操作列出目录内容
        # 参数：target_path - 目标路径，root - 根目录，recursive - 是否递归，limit - 结果限制，stat_op - stat 操作，readdir_op - readdir 操作
        # 返回值：ListEntry 结构体数组
        def self.list_directory_with_ops(target_path, root, recursive, limit, stat_op:, readdir_op:)
          target_stat = stat_op.call(target_path)
          return [make_list_entry(target_path, root, target_stat)] unless target_stat.directory?

          unless recursive
            entries = readdir_op.call(target_path).sort_by { |e| e[:name] }.first(limit)
            return entries.filter_map do |entry|
              entry_path = File.join(target_path, entry[:name])
              make_list_entry(entry_path, root, stat_op.call(entry_path))
            end
          end

          list_directory(target_path, root, recursive, limit)
        end

        # 方法功能：从路径创建 ListEntry
        # 参数：path - 路径，root - 根目录，file_stat - 文件状态
        # 返回值：ListEntry 结构体实例
        def self.make_list_entry(path, root, file_stat)
          kind = if file_stat.directory?
                   'directory'
                 elsif file_stat.file?
                   'file'
                 elsif file_stat.symlink?
                   'symlink'
                 else
                   'other'
                 end

          ListEntry.new(
            path: path,
            relative_path: Pathname.new(path).relative_path_from(Pathname.new(root)).to_s,
            name: File.basename(path),
            kind: kind,
            size: file_stat.size
          )
        end

        # 方法功能：编译 grep 模式
        # 参数：pattern - 模式字符串，literal - 是否字面量匹配
        # 返回值：正则表达式
        def self.compile_pattern(pattern, literal)
          if literal
            escaped = Regexp.escape(pattern)
            Regexp.new(escaped, Regexp::IGNORECASE)
          else
            Regexp.new(pattern, Regexp::IGNORECASE)
          end
        end

        # 方法功能：将值规范化为正整数
        # 参数：value - 输入值，fallback - 备用值
        # 返回值：正整数或备用值
        def self.normalize_positive_integer(value, fallback)
          if value.is_a?(Numeric) && value.finite? && value.positive?
            value.to_i
          else
            fallback
          end
        end

        # 方法功能：将值规范化为布尔值
        # 参数：value - 输入值，fallback - 备用值
        # 返回值：布尔值
        def self.normalize_boolean(value, fallback = false)
          return value if [true, false].include?(value)

          fallback
        end

        # 方法功能：将 glob 模式转换为正则表达式
        # 参数：pattern - glob 模式字符串
        # 返回值：正则表达式
        def self.glob_to_regexp(pattern)
          optional_prefix = pattern.start_with?('**/')
          normalized_pattern = optional_prefix ? pattern[3..] : pattern

          escaped = Regexp.escape(normalized_pattern)
          with_wildcards = escaped
                           .gsub('\\*\\*', '.*')
                           .gsub('\\*', '[^/]*')
                           .gsub('\\?', '.')

          prefix = optional_prefix ? '(?:.*/)?' : ''
          Regexp.new("^#{prefix}#{with_wildcards}$", Regexp::IGNORECASE)
        end

        # 方法功能：标准化路径分隔符
        # 参数：value - 路径字符串
        # 返回值：标准化后的路径
        def self.normalize_tool_path(value)
          value.gsub('\\', '/')
        end

        # 方法功能：从参数中解析编辑指令
        # 参数：args - 参数哈希
        # 返回值：EditInstruction 结构体数组
        def self.parse_edit_instructions(args)
          if args[:edits].is_a?(Array)
            edits = args[:edits].filter_map do |value|
              next unless value.is_a?(Hash)
              next unless value[:old_text].is_a?(String) && value[:new_text].is_a?(String)

              EditInstruction.new(old_text: value[:old_text], new_text: value[:new_text])
            end
            return edits unless edits.empty?
          end

          if args[:old_text].is_a?(String) && args[:new_text].is_a?(String)
            [EditInstruction.new(old_text: args[:old_text], new_text: args[:new_text])]
          else
            []
          end
        end

        # 方法功能：查找 needle 在 source 中的所有出现位置
        # 参数：source - 源字符串，needle - 查找字符串
        # 返回值：位置索引数组
        def self.find_occurrences(source, needle)
          return [] if needle.empty?

          matches = []
          index = 0
          loop do
            next_index = source.index(needle, index)
            break unless next_index

            matches << next_index
            index = next_index + [1, needle.length].max
          end
          matches
        end

        # 方法功能：对源代码应用精确文本编辑
        # 参数：source - 源代码字符串，edits - 编辑指令数组
        # 返回值：包含 :next 和 :replacements 的哈希
        def self.apply_exact_text_edits(source, edits)
          planned = edits.each_with_index.map do |edit, index|
            matches = find_occurrences(source, edit.old_text)
            raise "edits[#{index}].old_text was not found in the target file" if matches.empty?
            if matches.length > 1
              raise "edits[#{index}].old_text matched #{matches.length} locations; each edit must be unique in the original file"
            end

            {
              start: matches[0],
              end: matches[0] + edit.old_text.length,
              new_text: edit.new_text
            }
          end

          sorted = planned.sort_by { |p| p[:start] }
          sorted.each_cons(2) do |previous, current|
            if current[:start] < previous[:end]
              raise 'edit ranges overlap in the original file; merge nearby changes into one edit'
            end
          end

          next_content = source.dup
          sorted.sort_by { |p| -p[:start] }.each do |patch|
            next_content = "#{next_content[0...patch[:start]]}#{patch[:new_text]}#{next_content[patch[:end]..]}"
          end

          { next: next_content, replacements: sorted.length }
        end
      end
    end
  end
end
