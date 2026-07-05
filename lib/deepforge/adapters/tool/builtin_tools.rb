# frozen_string_literal: true

# 文件用途：内置工具的工厂模块
# 使用方法：通过 create_builtin_local_tool 或 build_builtin_local_tools 创建各类内置工具

require_relative 'builtin_tool_types'
require_relative 'builtin_tool_operations'
require_relative 'local_tool_host'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：内置工具的工厂，负责创建和组合各类本地工具
      module BuiltinTools
        # 方法功能：创建单个内置本地工具
        # 参数：tool_name - 工具名称（'read'、'bash'、'edit'、'write'、'grep'、'find'、'ls'）
        #       options - 工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_builtin_local_tool(tool_name, options = BuiltinLocalToolsOptions.new)
          case tool_name
          when 'read'
            create_read_local_tool(options.read)
          when 'bash'
            create_bash_local_tool(options.bash)
          when 'edit'
            create_edit_local_tool(options.edit)
          when 'write'
            create_write_local_tool(options.write)
          when 'grep'
            create_grep_local_tool(options.grep)
          when 'find'
            create_find_local_tool(options.find)
          when 'ls'
            create_ls_local_tool(options.ls)
          else
            raise "unknown tool: #{tool_name}"
          end
        end

        # 方法功能：按名称创建工具（create_builtin_local_tool 的别名）
        # 参数：tool_name - 工具名称，options - 工具选项
        # 返回值：LocalTool 实例
        def self.create_tool(tool_name, options = ToolsOptions.new)
          create_builtin_local_tool(tool_name, options)
        end

        # 方法功能：创建工具定义（create_builtin_local_tool 的别名）
        # 参数：tool_name - 工具名称，options - 工具选项
        # 返回值：LocalTool 实例
        def self.create_tool_definition(tool_name, options = ToolsOptions.new)
          create_builtin_local_tool(tool_name, options)
        end

        # 方法功能：构建所有内置本地工具
        # 参数：options - 内置工具选项
        # 返回值：LocalTool 数组
        def self.build_builtin_local_tools(options = BuiltinLocalToolsOptions.new)
          [
            create_read_local_tool(options.read),
            create_bash_local_tool(options.bash),
            create_edit_local_tool(options.edit),
            create_write_local_tool(options.write),
            create_grep_local_tool(options.grep),
            create_find_local_tool(options.find),
            create_ls_local_tool(options.ls)
          ]
        end

        # 方法功能：将所有工具创建为哈希
        # 参数：options - 工具选项
        # 返回值：工具名称到 LocalTool 的映射
        def self.create_all_tools(options = ToolsOptions.new)
          build_builtin_local_tool_record(options)
        end

        # 方法功能：构建仅编码的内置工具（read、bash、edit、write）
        # 参数：options - 内置工具选项
        # 返回值：LocalTool 数组
        def self.build_coding_builtin_local_tools(options = BuiltinLocalToolsOptions.new)
          [
            create_read_local_tool(options.read),
            create_bash_local_tool(options.bash),
            create_edit_local_tool(options.edit),
            create_write_local_tool(options.write)
          ]
        end

        # 方法功能：创建编码工具
        # 参数：options - 工具选项
        # 返回值：LocalTool 数组
        def self.create_coding_tools(options = ToolsOptions.new)
          build_coding_builtin_local_tools(options)
        end

        # 方法功能：构建只读内置工具（read、grep、find、ls）
        # 参数：options - 内置工具选项
        # 返回值：LocalTool 数组
        def self.build_read_only_builtin_local_tools(options = BuiltinLocalToolsOptions.new)
          [
            create_read_local_tool(options.read),
            create_grep_local_tool(options.grep),
            create_find_local_tool(options.find),
            create_ls_local_tool(options.ls)
          ]
        end

        # 方法功能：创建只读工具
        # 参数：options - 工具选项
        # 返回值：LocalTool 数组
        def self.create_read_only_tools(options = ToolsOptions.new)
          build_read_only_builtin_local_tools(options)
        end

        # 方法功能：将内置工具构建为哈希记录
        # 参数：options - 内置工具选项
        # 返回值：工具名称到 LocalTool 的映射
        def self.build_builtin_local_tool_record(options = BuiltinLocalToolsOptions.new)
          {
            'read' => create_read_local_tool(options.read),
            'bash' => create_bash_local_tool(options.bash),
            'edit' => create_edit_local_tool(options.edit),
            'write' => create_write_local_tool(options.write),
            'grep' => create_grep_local_tool(options.grep),
            'find' => create_find_local_tool(options.find),
            'ls' => create_ls_local_tool(options.ls)
          }
        end

        # 方法功能：创建所有工具定义
        # 参数：options - 工具选项
        # 返回值：工具名称到 LocalTool 的映射
        def self.create_all_tool_definitions(options = ToolsOptions.new)
          build_builtin_local_tool_record(options)
        end

        # 方法功能：创建编码工具定义
        # 参数：options - 工具选项
        # 返回值：LocalTool 数组
        def self.create_coding_tool_definitions(options = ToolsOptions.new)
          build_coding_builtin_local_tools(options)
        end

        # 方法功能：创建只读工具定义
        # 参数：options - 工具选项
        # 返回值：LocalTool 数组
        def self.create_read_only_tool_definitions(options = ToolsOptions.new)
          build_read_only_builtin_local_tools(options)
        end

        # 方法功能：创建读取工具
        # 参数：options - 读取工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_read_local_tool(options = nil)
          options ||= ReadLocalToolOptions.new
          ops = options.operations || BuiltinToolOperations.default_read_local_tool_operations

          LocalToolHost.define_tool(
            name: 'read',
            description: 'Read file contents with path and optional offset/limit.',
            tool_kind: TOOL_KIND_FILE_CHANGE,
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                offset: { type: 'number' },
                limit: { type: 'number' }
              },
              required: ['path']
            },
            policy: POLICY_AUTO,
            execute: create_read_execute_lambda(ops, options)
          )
        end

        # 方法功能：创建 bash 工具
        # 参数：options - bash 工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_bash_local_tool(options = nil)
          options ||= BashLocalToolOptions.new
          ops = options.operations || BuiltinToolOperations.create_local_bash_operations
          timeout = options.default_timeout_seconds || DEFAULT_BASH_TIMEOUT_SECONDS

          LocalToolHost.define_tool(
            name: 'bash',
            description: 'Execute a shell command.',
            tool_kind: TOOL_KIND_COMMAND_EXECUTION,
            input_schema: {
              type: 'object',
              properties: {
                command: { type: 'string' }
              },
              required: ['command']
            },
            policy: POLICY_ON_REQUEST,
            execute: create_bash_execute_lambda(ops, timeout)
          )
        end

        # 方法功能：创建编辑工具
        # 参数：options - 编辑工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_edit_local_tool(options = nil)
          options ||= EditLocalToolOptions.new
          ops = options.operations || BuiltinToolOperations.default_edit_local_tool_operations

          LocalToolHost.define_tool(
            name: 'edit',
            description: 'Edit file contents with old/new text replacement.',
            tool_kind: TOOL_KIND_FILE_CHANGE,
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                old_text: { type: 'string' },
                new_text: { type: 'string' }
              },
              required: %w[path old_text new_text]
            },
            policy: POLICY_ON_REQUEST,
            execute: create_edit_execute_lambda(ops)
          )
        end

        # 方法功能：创建写入工具
        # 参数：options - 写入工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_write_local_tool(options = nil)
          options ||= WriteLocalToolOptions.new
          ops = options.operations || BuiltinToolOperations.default_write_local_tool_operations

          LocalToolHost.define_tool(
            name: 'write',
            description: 'Write content to a file.',
            tool_kind: TOOL_KIND_FILE_CHANGE,
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                content: { type: 'string' }
              },
              required: %w[path content]
            },
            policy: POLICY_ON_REQUEST,
            execute: create_write_execute_lambda(ops)
          )
        end

        # 方法功能：创建搜索工具
        # 参数：options - 搜索工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_grep_local_tool(options = nil)
          options ||= GrepLocalToolOptions.new
          ops = options.operations || BuiltinToolOperations.default_grep_local_tool_operations

          LocalToolHost.define_tool(
            name: 'grep',
            description: 'Search file contents using regex patterns.',
            tool_kind: TOOL_KIND_TOOL_CALL,
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
              required: ['pattern']
            },
            policy: POLICY_AUTO,
            execute: create_grep_execute_lambda(ops, options)
          )
        end

        # 方法功能：创建查找工具
        # 参数：options - 查找工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_find_local_tool(options = nil)
          options ||= FindLocalToolOptions.new
          ops = options.operations || BuiltinToolOperations.default_find_local_tool_operations

          LocalToolHost.define_tool(
            name: 'find',
            description: 'Find files by name pattern.',
            tool_kind: TOOL_KIND_TOOL_CALL,
            input_schema: {
              type: 'object',
              properties: {
                pattern: { type: 'string' },
                path: { type: 'string' },
                limit: { type: 'number' }
              },
              required: ['pattern']
            },
            policy: POLICY_AUTO,
            execute: create_find_execute_lambda(ops, options)
          )
        end

        # 方法功能：创建列表工具
        # 参数：options - 列表工具选项（可选）
        # 返回值：LocalTool 实例
        def self.create_ls_local_tool(options = nil)
          options ||= LsLocalToolOptions.new
          ops = options.operations || BuiltinToolOperations.default_ls_local_tool_operations

          LocalToolHost.define_tool(
            name: 'ls',
            description: 'List directory contents.',
            tool_kind: TOOL_KIND_TOOL_CALL,
            input_schema: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                recursive: { type: 'boolean' },
                limit: { type: 'number' }
              },
              required: ['path']
            },
            policy: POLICY_AUTO,
            execute: create_ls_execute_lambda(ops, options)
          )
        end

        class << self
          private

          # 方法功能：为读取工具创建执行 lambda
          # 参数：ops - 操作函数，options - 选项
          # 返回值：执行 lambda
          def create_read_execute_lambda(ops, options)
            lambda do |args, context, &_block|
              BuiltinToolUtils.with_tool_boundary do
                path = args[:path].to_s
                resolved = BuiltinToolUtils.resolve_workspace_path(path, context)

                ops.stat.call(resolved[:absolute_path])
                max_bytes = options.max_bytes || (50 * 1024)
                max_lines = options.max_lines || 2000

                buffer = ops.read_file.call(resolved[:absolute_path])
                content = buffer.encode('UTF-8', invalid: :replace, undef: :replace)

                truncated = false
                if content.bytesize > max_bytes
                  content = content.byteslice(0, max_bytes)
                  truncated = true
                end

                lines = content.split("\n")
                if lines.length > max_lines
                  content = lines.first(max_lines).join("\n")
                  truncated = true
                end

                {
                  output: {
                    path: resolved[:relative_path],
                    content: content,
                    truncated: truncated,
                    total_lines: lines.length,
                    total_bytes: buffer.bytesize
                  }
                }
              end
            end
          end

          # 方法功能：为 bash 工具创建执行 lambda
          # 参数：ops - 操作函数，timeout - 超时时间
          # 返回值：执行 lambda
          def create_bash_execute_lambda(ops, timeout)
            lambda do |args, context, &_block|
              BuiltinToolUtils.with_tool_boundary do
                command = args[:command].to_s
                result = ops.exec.call(command, context.workspace, {
                                         signal: context.abort_signal,
                                         timeout_seconds: timeout
                                       })
                { output: { exit_code: result[:exit_code] } }
              end
            end
          end

          # 方法功能：为编辑工具创建执行 lambda
          # 参数：ops - 操作函数
          # 返回值：执行 lambda
          def create_edit_execute_lambda(ops)
            lambda do |args, context, &_block|
              BuiltinToolUtils.with_tool_boundary do
                path = args[:path].to_s
                resolved = BuiltinToolUtils.resolve_workspace_path(path, context)
                old_text = args[:old_text].to_s
                new_text = args[:new_text].to_s

                content = ops.read_file.call(resolved[:absolute_path])
                edits = [EditInstruction.new(old_text: old_text, new_text: new_text)]
                result = BuiltinToolUtils.apply_exact_text_edits(content, edits)
                ops.write_file.call(resolved[:absolute_path], result[:next])

                { output: { replacements: result[:replacements] } }
              end
            end
          end

          # 方法功能：为写入工具创建执行 lambda
          # 参数：ops - 操作函数
          # 返回值：执行 lambda
          def create_write_execute_lambda(ops)
            lambda do |args, context, &_block|
              BuiltinToolUtils.with_tool_boundary do
                path = args[:path].to_s
                resolved = BuiltinToolUtils.resolve_workspace_path(path, context)
                content = args[:content].to_s

                dir = File.dirname(resolved[:absolute_path])
                ops.mkdir.call(dir) unless Dir.exist?(dir)
                ops.write_file.call(resolved[:absolute_path], content)

                { output: { path: resolved[:relative_path], bytes: content.bytesize } }
              end
            end
          end

          # 方法功能：为搜索工具创建执行 lambda
          # 参数：ops - 操作函数，options - 选项
          # 返回值：执行 lambda
          def create_grep_execute_lambda(ops, options)
            lambda do |args, context, &_block|
              BuiltinToolUtils.with_tool_boundary do
                pattern = args[:pattern].to_s
                path = args[:path]&.to_s || context.workspace
                resolved = BuiltinToolUtils.resolve_workspace_path(path, context)
                limit = options.default_limit || DEFAULT_SEARCH_LIMIT

                if ops.search
                  results = ops.search.call({
                                              pattern: pattern,
                                              path: resolved[:absolute_path],
                                              glob: args[:glob]&.to_s,
                                              ignore_case: BuiltinToolUtils.normalize_boolean(args[:ignore_case]),
                                              literal: BuiltinToolUtils.normalize_boolean(args[:literal]),
                                              context: BuiltinToolUtils.normalize_positive_integer(args[:context], 0),
                                              limit: limit
                                            })
                  { output: { matches: results } }
                else
                  { output: { error: 'grep search not implemented' }, is_error: true }
                end
              end
            end
          end

          # 方法功能：为查找工具创建执行 lambda
          # 参数：ops - 操作函数，options - 选项
          # 返回值：执行 lambda
          def create_find_execute_lambda(ops, options)
            lambda do |args, context, &_block|
              BuiltinToolUtils.with_tool_boundary do
                pattern = args[:pattern].to_s
                path = args[:path]&.to_s || context.workspace
                resolved = BuiltinToolUtils.resolve_workspace_path(path, context)
                limit = options.default_limit || DEFAULT_FIND_LIMIT

                if ops.glob
                  results = ops.glob.call({
                                            pattern: pattern,
                                            path: resolved[:absolute_path],
                                            limit: limit
                                          })
                  { output: { paths: results } }
                else
                  { output: { error: 'find glob not implemented' }, is_error: true }
                end
              end
            end
          end

          # 方法功能：为列表工具创建执行 lambda
          # 参数：ops - 操作函数，options - 选项
          # 返回值：执行 lambda
          def create_ls_execute_lambda(_ops, options)
            lambda do |args, context, &_block|
              BuiltinToolUtils.with_tool_boundary do
                path = args[:path].to_s
                resolved = BuiltinToolUtils.resolve_workspace_path(path, context)
                recursive = BuiltinToolUtils.normalize_boolean(args[:recursive])
                limit = options.default_limit || DEFAULT_LIST_LIMIT

                entries = BuiltinToolUtils.list_directory(
                  resolved[:absolute_path],
                  resolved[:workspace_root],
                  recursive,
                  limit
                )

                { output: { entries: entries.map do |e|
                  { path: e.relative_path, name: e.name, kind: e.kind, size: e.size }
                end } }
              end
            end
          end
        end
      end
    end
  end
end
