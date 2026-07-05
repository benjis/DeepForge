# frozen_string_literal: true

# 文件用途：内置搜索工具（ls、find、grep）的完整实现
# 使用方法：通过 create_ls_tool、create_find_tool、create_grep_tool 创建对应工具

require 'open3'
require 'find'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供目录列表、文件查找和内容搜索的内置工具
      module BuiltinSearchTools
        # 默认 grep 搜索结果限制
        DEFAULT_SEARCH_LIMIT = 100
        # 默认 ls 列表结果限制
        DEFAULT_LIST_LIMIT = 500
        # 默认 find 查找结果限制
        DEFAULT_FIND_LIMIT = 1000

        # Find 工具选项结构体
        FindLocalToolOptions = Struct.new(:default_limit, :fd_executable_candidates, :rg_executable_candidates,
                                          :operations, keyword_init: true)
        # Grep 工具选项结构体
        GrepLocalToolOptions = Struct.new(:default_limit, :rg_executable_candidates, :operations, keyword_init: true)
        # Ls 工具选项结构体
        LsLocalToolOptions = Struct.new(:default_limit, :operations, keyword_init: true)

        # Grep 匹配结果结构体
        GrepMatch = Struct.new(:path, :relative_path, :line, :column, :text, :context_before, :context_after,
                               keyword_init: true)
        # 目录列表条目结构体
        ListEntry = Struct.new(:path, :relative_path, :name, :kind, :size, keyword_init: true)

        # 方法功能：创建目录列表工具
        # 参数：options - Ls 工具选项（可选）
        # 返回值：包含工具定义的哈希
        def self.create_ls_tool(options = {})
          options ||= LsLocalToolOptions.new
          options.operations&.stat
          options.operations&.readdir

          {
            name: 'ls',
            description: 'List directory contents. Returns entries sorted alphabetically and marks directories.',
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                limit: { type: 'number' }
              },
              required: [],
              additional_properties: false
            },
            policy: 'auto',
            execute: ->(args, context) { execute_ls(args, context, options) }
          }
        end

        # 方法功能：创建文件查找工具
        # 参数：options - Find 工具选项（可选）
        # 返回值：包含工具定义的哈希
        def self.create_find_tool(options = {})
          options ||= FindLocalToolOptions.new

          {
            name: 'find',
            description: 'Find workspace files by glob pattern, similar to pi find.',
            input_schema: {
              type: 'object',
              properties: {
                pattern: { type: 'string' },
                path: { type: 'string' },
                limit: { type: 'number' }
              },
              required: ['pattern'],
              additional_properties: false
            },
            policy: 'auto',
            execute: ->(args, context) { execute_find(args, context, options) }
          }
        end

        # 方法功能：创建内容搜索工具
        # 参数：options - Grep 工具选项（可选）
        # 返回值：包含工具定义的哈希
        def self.create_grep_tool(options = {})
          options ||= GrepLocalToolOptions.new

          {
            name: 'grep',
            description: 'Search file contents for a pattern and return matching lines with paths and line numbers.',
            input_schema: {
              type: 'object',
              properties: {
                pattern: { type: 'string' },
                path: { type: 'string' },
                glob: { type: 'string' },
                ignore_case: { type: 'boolean' },
                literal: { type: 'boolean' },
                context: { type: 'number' },
                limit: { type: 'number' }
              },
              required: ['pattern'],
              additional_properties: false
            },
            policy: 'auto',
            execute: ->(args, context) { execute_grep(args, context, options) }
          }
        end

        # 方法功能：执行目录列表操作
        # 参数：args - 参数哈希，context - 上下文，options - 选项
        # 返回值：包含目录内容的哈希
        def self.execute_ls(args, context, options)
          raw_path = args[:path].to_s.strip
          raw_path = '.' if raw_path.empty?
          limit = normalize_positive_integer(args[:limit], options.default_limit || DEFAULT_LIST_LIMIT)

          absolute_path = resolve_workspace_path(raw_path, context)
          relative_path = make_relative(absolute_path, context)

          return error_output("not a directory: #{absolute_path}") unless File.directory?(absolute_path)

          entries = list_directory(absolute_path, context[:workspace] || Dir.pwd, limit)

          {
            output: {
              path: absolute_path,
              relative_path: relative_path,
              entries: entries.map { |e| e.to_h.merge(display_name: e.kind == 'directory' ? "#{e.name}/" : e.name) },
              names: entries.map { |e| e.kind == 'directory' ? "#{e.name}/" : e.name },
              truncated: entries.length >= limit,
              entry_limit_reached: entries.length >= limit ? limit : nil
            }
          }
        end

        # 方法功能：执行文件查找操作
        # 参数：args - 参数哈希，context - 上下文，options - 选项
        # 返回值：包含查找结果的哈希
        def self.execute_find(args, context, options)
          pattern = args[:pattern].to_s.strip
          return error_output('pattern is required') if pattern.empty?

          raw_path = args[:path].to_s.strip
          raw_path = '.' if raw_path.empty?
          limit = normalize_positive_integer(args[:limit], options.default_limit || DEFAULT_FIND_LIMIT)

          absolute_path = resolve_workspace_path(raw_path, context)
          relative_path = make_relative(absolute_path, context)

          rg = resolve_rg_executable(options.rg_executable_candidates)

          matches = if rg
                      find_with_rg(rg, pattern, absolute_path, context[:workspace] || Dir.pwd, limit, context)
                    else
                      find_with_glob(pattern, absolute_path, context[:workspace] || Dir.pwd, limit)
                    end

          {
            output: {
              path: absolute_path,
              relative_path: relative_path,
              pattern: pattern,
              matches: matches,
              backend: rg ? 'rg' : 'scan',
              truncated: matches.length >= limit,
              result_limit_reached: matches.length >= limit ? limit : nil
            }
          }
        end

        # 方法功能：执行内容搜索操作
        # 参数：args - 参数哈希，context - 上下文，options - 选项
        # 返回值：包含搜索结果的哈希
        def self.execute_grep(args, context, options)
          pattern = args[:pattern].to_s
          return error_output('pattern is required') if pattern.strip.empty?

          literal = args[:literal] == true
          ignore_case = args[:ignore_case] == true
          context_lines = args[:context].is_a?(Numeric) && args[:context].positive? ? args[:context].to_i : 0
          glob = args[:glob].to_s.strip
          glob = nil if glob.empty?
          limit = normalize_positive_integer(args[:limit], options.default_limit || DEFAULT_SEARCH_LIMIT)

          raw_path = args[:path].to_s.strip
          raw_path = '.' if raw_path.empty?

          flags = ignore_case ? Regexp::IGNORECASE : 0
          effective_matcher = if literal
                                Regexp.new(Regexp.escape(pattern), flags)
                              else
                                Regexp.new(pattern, flags)
                              end

          absolute_path = resolve_workspace_path(raw_path, context)
          relative_path = make_relative(absolute_path, context)

          rg = resolve_rg_executable(options.rg_executable_candidates)

          matches = if rg
                      grep_with_rg(rg, pattern, absolute_path, context[:workspace] || Dir.pwd, effective_matcher, glob,
                                   ignore_case, literal, context_lines, limit, context)
                    else
                      grep_with_scan(pattern, absolute_path, context[:workspace] || Dir.pwd, effective_matcher, glob,
                                     context_lines, limit)
                    end

          {
            output: {
              path: absolute_path,
              relative_path: relative_path,
              pattern: pattern,
              glob: glob,
              ignore_case: ignore_case,
              literal: literal,
              context: context_lines,
              backend: rg ? 'rg' : 'scan',
              matches: matches,
              truncated: matches.length >= limit,
              match_limit_reached: matches.length >= limit ? limit : nil
            }
          }
        end

        # 方法功能：列出目录内容
        # 参数：absolute_path - 绝对路径，workspace_root - 工作区根目录，limit - 结果限制
        # 返回值：ListEntry 结构体数组
        def self.list_directory(absolute_path, workspace_root, limit)
          entries = []
          Dir.entries(absolute_path).sort.each do |name|
            break if entries.length >= limit
            next if ['.', '..'].include?(name)

            full_path = File.join(absolute_path, name)
            stat = begin
              File.stat(full_path)
            rescue StandardError
              nil
            end
            next unless stat

            kind = if stat.directory?
                     'directory'
                   elsif stat.symlink?
                     'symlink'
                   elsif stat.file?
                     'file'
                   else
                     'other'
                   end

            relative = begin
              Pathname.new(full_path).relative_path_from(Pathname.new(workspace_root)).to_s
            rescue ArgumentError
              full_path
            end

            entries << ListEntry.new(
              path: full_path,
              relative_path: relative,
              name: name,
              kind: kind,
              size: stat.size
            )
          end
          entries
        end

        # 方法功能：使用 rg 工具执行文件查找
        # 参数：rg - rg 可执行文件路径，pattern - 匹配模式，absolute_path - 绝对路径，workspace_root - 工作区根目录，limit - 结果限制，context - 上下文
        # 返回值：匹配结果数组
        def self.find_with_rg(rg, pattern, absolute_path, workspace_root, limit, _context)
          cmd = [rg, '--files', '--hidden', '-g', pattern, absolute_path]
          stdout, _stderr, status = Open3.capture3(*cmd, chdir: workspace_root)

          return [] unless status.success?

          stdout.split("\n").map(&:strip).reject(&:empty?).first(limit).map do |path|
            full_path = File.expand_path(path, workspace_root)
            relative = begin
              Pathname.new(full_path).relative_path_from(Pathname.new(workspace_root)).to_s
            rescue ArgumentError
              full_path
            end
            { path: full_path, relative_path: relative }
          end
        end

        # 方法功能：使用 glob 模式执行文件查找
        # 参数：pattern - 匹配模式，absolute_path - 绝对路径，workspace_root - 工作区根目录，limit - 结果限制
        # 返回值：匹配结果数组
        def self.find_with_glob(pattern, absolute_path, workspace_root, limit)
          glob_pattern = pattern.include?('/') ? pattern : "**/#{pattern}"
          matches = Dir.glob(glob_pattern, base: absolute_path).first(limit * 8)

          matches.filter_map do |rel|
            full_path = File.join(absolute_path, rel)
            next unless File.file?(full_path)

            relative = begin
              Pathname.new(full_path).relative_path_from(Pathname.new(workspace_root)).to_s
            rescue ArgumentError
              full_path
            end
            { path: full_path, relative_path: relative }
          end.first(limit)
        end

        # 方法功能：使用 rg 工具执行内容搜索
        # 参数：rg - rg 可执行文件路径，pattern - 搜索模式，absolute_path - 绝对路径，workspace_root - 工作区根目录，matcher - 正则匹配器，glob - 文件过滤模式，ignore_case - 忽略大小写，literal - 字面量匹配，context_lines - 上下文行数，limit - 结果限制，context - 上下文
        # 返回值：匹配结果数组
        def self.grep_with_rg(rg, pattern, absolute_path, workspace_root, matcher, glob, ignore_case, literal,
                              context_lines, limit, _context)
          cmd = [rg, '--hidden', '--line-number', '--with-filename', '--color', 'never']
          cmd << '--ignore-case' if ignore_case
          cmd << '--fixed-strings' if literal
          cmd += ['-g', glob] if glob
          cmd += [pattern, absolute_path]

          stdout, _stderr, status = Open3.capture3(*cmd, chdir: workspace_root)
          return [] unless status.success?

          matches = []
          stdout.split("\n").map(&:strip).reject(&:empty?).each do |row|
            break if matches.length >= limit

            parsed = row.match(/^(.*?):(\d+):(.*)$/)
            next unless parsed

            candidate_path = File.expand_path(parsed[1], workspace_root)
            line_number = parsed[2].to_i
            line_text = parsed[3]

            candidate_relative = begin
              Pathname.new(candidate_path).relative_path_from(Pathname.new(workspace_root)).to_s
            rescue ArgumentError
              candidate_path
            end

            next if binary_file?(candidate_path)

            lines = File.read(candidate_path).gsub("\r\n", "\n").split("\n")
            column_match = matcher.match(line_text)

            match_data = {
              path: candidate_path,
              relative_path: candidate_relative,
              line: line_number,
              column: (column_match&.begin(0) || 0) + 1,
              text: line_text
            }

            if context_lines.positive?
              match_data[:context_before] = lines[[0, line_number - 1 - context_lines].max...(line_number - 1)]
              match_data[:context_after] = lines[line_number...(line_number + context_lines)]
            end

            matches << match_data
          end
          matches
        end

        # 方法功能：使用扫描方式执行内容搜索
        # 参数：pattern - 搜索模式，absolute_path - 绝对路径，workspace_root - 工作区根目录，matcher - 正则匹配器，glob - 文件过滤模式，context_lines - 上下文行数，limit - 结果限制
        # 返回值：匹配结果数组
        def self.grep_with_scan(_pattern, absolute_path, workspace_root, matcher, glob, context_lines, limit)
          glob_pattern = if glob
                           glob.include?('/') ? glob : "**/#{glob}"
                         else
                           '**/*'
                         end
          candidates = Dir.glob(glob_pattern, base: absolute_path).map { |f| File.join(absolute_path, f) }

          matches = []
          candidates.each do |candidate_path|
            break if matches.length >= limit
            next unless File.file?(candidate_path)

            candidate_relative = begin
              Pathname.new(candidate_path).relative_path_from(Pathname.new(workspace_root)).to_s
            rescue ArgumentError
              candidate_path
            end

            next if binary_file?(candidate_path)

            lines = File.read(candidate_path).gsub("\r\n", "\n").split("\n")
            lines.each_with_index do |line, index|
              result = matcher.match(line)
              next unless result

              match_data = {
                path: candidate_path,
                relative_path: candidate_relative,
                line: index + 1,
                column: result.begin(0) + 1,
                text: line
              }

              if context_lines.positive?
                match_data[:context_before] = lines[[0, index - context_lines].max...index]
                match_data[:context_after] = lines[(index + 1)..(index + 1 + context_lines)]
              end

              matches << match_data
              break if matches.length >= limit
            end
          end
          matches
        end

        # 方法功能：检测文件是否为二进制文件
        # 参数：path - 文件路径
        # 返回值：布尔值
        def self.binary_file?(path)
          sample = File.binread(path, [8192, File.size(path)].min)
          sample.include?("\x00")
        rescue StandardError
          true
        end

        # 方法功能：解析 rg 可执行文件路径
        # 参数：candidates - 候选路径数组
        # 返回值：可执行文件路径或 nil
        def self.resolve_rg_executable(candidates)
          default_candidates = ['/Applications/Codex.app/Contents/Resources/rg', 'rg']
          all_candidates = (candidates || []) + default_candidates

          all_candidates.each do |candidate|
            return candidate if system("which #{candidate} > /dev/null 2>&1")
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

        # 方法功能：将值规范化为正整数
        # 参数：value - 输入值，default - 默认值
        # 返回值：正整数或默认值
        def self.normalize_positive_integer(value, default)
          return default if value.nil?

          int_val = value.to_i
          int_val.positive? ? int_val : default
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
