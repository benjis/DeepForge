# frozen_string_literal: true

# 文件用途：内置 Bash 工具的完整实现
# 使用方法：通过 create 方法创建 bash 工具定义，支持在工作区中执行 shell 命令并返回输出

require 'open3'
require 'tmpdir'
require 'fileutils'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供内置的 Bash 命令执行工具
      # 支持命令执行、超时控制、输出截断等功能
      module BuiltinBashTool
        # 默认 bash 命令超时时间（秒）
        DEFAULT_BASH_TIMEOUT_SECONDS = 120
        # 默认输出最大行数
        DEFAULT_MAX_LINES = 2000
        # 默认输出最大字节数
        DEFAULT_MAX_BYTES = 512_000

        # Bash 操作结构体，包含 exec 执行函数
        BashOperations = Struct.new(:exec, keyword_init: true)
        # Bash 工具选项结构体，包含超时时间和操作函数
        BashToolOptions = Struct.new(:default_timeout_seconds, :operations, keyword_init: true)

        # 文本切片结构体，用于描述截断后的输出信息
        TextSlice = Struct.new(
          :text, :truncated, :total_lines, :shown_lines,
          :total_bytes, :shown_bytes, :first_line_exceeds_limit,
          :truncated_by, :last_line_partial,
          keyword_init: true
        )

        # 方法功能：创建 Bash 工具定义
        # 参数：options - Bash 工具选项（可选）
        # 返回值：包含工具元数据和执行逻辑的哈希
        def self.create(options = {})
          options ||= BashToolOptions.new
          bash_ops = options.operations || create_operations

          {
            name: 'bash',
            description: 'Execute a shell command in the workspace and return the combined stdout and stderr output.',
            input_schema: {
              type: 'object',
              properties: {
                command: { type: 'string' },
                timeout: { type: 'number' }
              },
              required: ['command'],
              additional_properties: false
            },
            policy: 'on-request',
            tool_kind: 'command_execution',
            execute: ->(args, context, _on_update = nil) { execute_bash(args, context, bash_ops, options) }
          }
        end

        # 方法功能：创建默认的 Bash 操作实例
        # 返回值：BashOperations 结构体实例
        def self.create_operations
          BashOperations.new(exec: nil)
        end

        # 方法功能：执行 bash 命令并返回结果
        # 参数：args - 命令参数哈希，context - 上下文，bash_ops - 操作函数，options - 选项
        # 返回值：包含命令输出和状态的哈希
        def self.execute_bash(args, context, bash_ops, options)
          command = args[:command].to_s.strip
          return error_output('command is required') if command.empty?

          timeout = normalize_positive_integer(
            args[:timeout],
            options&.default_timeout_seconds || DEFAULT_BASH_TIMEOUT_SECONDS
          )

          cwd = context[:workspace] || Dir.pwd
          FileUtils.mkdir_p(cwd)

          begin
            result = bash_execute(command, cwd, timeout, bash_ops)
            content = append_truncation_notice(result[:output], result[:truncated], :tail)

            if result[:exit_code] && result[:exit_code] != 0
              {
                output: {
                  command: command,
                  cwd: cwd,
                  exit_code: result[:exit_code],
                  output: content,
                  full_output_path: result[:full_output_path],
                  truncation: format_truncation(result[:truncated])
                },
                is_error: true
              }
            else
              {
                output: {
                  command: command,
                  cwd: cwd,
                  exit_code: result[:exit_code] || 0,
                  output: content,
                  full_output_path: result[:full_output_path],
                  truncation: format_truncation(result[:truncated])
                }
              }
            end
          rescue StandardError => e
            {
              output: {
                command: command,
                cwd: cwd,
                error: e.message
              },
              is_error: true
            }
          end
        end

        # 方法功能：根据操作函数选择执行方式
        # 参数：command - 命令字符串，cwd - 工作目录，timeout_seconds - 超时时间，bash_ops - 操作函数
        # 返回值：执行结果哈希
        def self.bash_execute(command, cwd, timeout_seconds, bash_ops)
          if bash_ops&.exec
            exec_via_operation(command, cwd, timeout_seconds, bash_ops.exec)
          else
            exec_via_spawn(command, cwd, timeout_seconds)
          end
        end

        # 方法功能：通过进程 spawn 执行命令
        # 参数：command - 命令字符串，cwd - 工作目录，timeout_seconds - 超时时间
        # 返回值：包含输出、退出码和截断信息的哈希
        def self.exec_via_spawn(command, cwd, timeout_seconds)
          output_accumulator = +''
          truncated = nil
          exit_code = nil

          Open3.popen3(command, chdir: cwd, in: :close) do |_stdin, stdout, stderr, wait_thr|
            stdout_thread = Thread.new do
              while (chunk = stdout.read(4096))
                output_accumulator << chunk
              end
            end

            stderr_thread = Thread.new do
              while (chunk = stderr.read(4096))
                output_accumulator << chunk
              end
            end

            begin
              Timeout.timeout(timeout_seconds) do
                stdout_thread.join
                stderr_thread.join
              end
            rescue Timeout::Error
              Process.kill('TERM', wait_thr.pid)
              sleep 0.5
              begin
                Process.kill('KILL', wait_thr.pid)
              rescue StandardError
                nil
              end
              raise "command timed out after #{timeout_seconds} seconds"
            end

            exit_code = wait_thr.value.exitstatus
            truncated = truncate_output(output_accumulator)
          end

          {
            output: truncated[:content],
            exit_code: exit_code,
            truncated: build_text_slice(truncated),
            full_output_path: truncated[:full_output_path]
          }
        end

        # 方法功能：通过自定义操作函数执行命令
        # 参数：command - 命令字符串，cwd - 工作目录，timeout_seconds - 超时时间，exec_fn - 执行函数
        # 返回值：包含输出、退出码和截断信息的哈希
        def self.exec_via_operation(command, cwd, timeout_seconds, exec_fn)
          output_accumulator = +''

          result = exec_fn.call(command, cwd, {
                                  timeout_seconds: timeout_seconds,
                                  onData: ->(data) { output_accumulator << data }
                                })

          truncated = truncate_output(output_accumulator)

          {
            output: truncated[:content],
            exit_code: result[:exit_code],
            truncated: build_text_slice(truncated),
            full_output_path: truncated[:full_output_path]
          }
        end

        # 方法功能：截断过长的输出文本
        # 参数：text - 原始输出文本
        # 返回值：包含截断后内容和截断信息的哈希
        def self.truncate_output(text)
          lines = text.split("\n")
          total_lines = lines.length
          total_bytes = text.bytesize

          if total_lines > DEFAULT_MAX_LINES || total_bytes > DEFAULT_MAX_BYTES
            truncated_lines = lines.last(DEFAULT_MAX_LINES)
            truncated_text = truncated_lines.join("\n")

            if truncated_text.bytesize > DEFAULT_MAX_BYTES
              truncated_text = truncated_text.byteslice(0, DEFAULT_MAX_BYTES)
            end

            {
              content: truncated_text,
              truncated: true,
              total_lines: total_lines,
              output_lines: truncated_lines.length,
              total_bytes: total_bytes,
              output_bytes: truncated_text.bytesize,
              truncated_by: total_lines > DEFAULT_MAX_LINES ? 'lines' : 'bytes',
              last_line_partial: !text.end_with?("\n"),
              full_output_path: nil
            }
          else
            {
              content: text,
              truncated: false,
              total_lines: total_lines,
              output_lines: total_lines,
              total_bytes: total_bytes,
              output_bytes: total_bytes,
              truncated_by: nil,
              last_line_partial: false,
              full_output_path: nil
            }
          end
        end

        # 方法功能：将截断信息构建为 TextSlice 结构体
        # 参数：truncated - 截断信息哈希
        # 返回值：TextSlice 结构体实例
        def self.build_text_slice(truncated)
          TextSlice.new(
            text: truncated[:content],
            truncated: truncated[:truncated],
            total_lines: truncated[:total_lines],
            shown_lines: truncated[:output_lines],
            total_bytes: truncated[:total_bytes],
            shown_bytes: truncated[:output_bytes],
            first_line_exceeds_limit: false,
            truncated_by: truncated[:truncated_by],
            last_line_partial: truncated[:last_line_partial]
          )
        end

        # 方法功能：在截断的输出末尾追加截断通知
        # 参数：text - 输出文本，truncated - 截断信息，mode - 模式
        # 返回值：添加通知后的文本
        def self.append_truncation_notice(text, truncated, _mode)
          return text unless truncated&.truncated

          prefix = text.strip
          notice = if truncated.first_line_exceeds_limit
                     "[first line exceeds #{DEFAULT_MAX_BYTES} bytes; refine the read range or use bash for a byte-limited slice]"
                   else
                     "[truncated: showing #{truncated.shown_lines} of #{truncated.total_lines} lines, " \
                       "#{truncated.shown_bytes} of #{truncated.total_bytes} bytes]"
                   end

          prefix.empty? ? notice : "#{prefix}\n\n#{notice}"
        end

        # 方法功能：格式化截断信息为输出格式
        # 参数：truncated - TextSlice 结构体
        # 返回值：格式化后的截断信息哈希或 nil
        def self.format_truncation(truncated)
          return nil unless truncated&.truncated

          {
            total_lines: truncated.total_lines,
            output_lines: truncated.shown_lines,
            total_bytes: truncated.total_bytes,
            output_bytes: truncated.shown_bytes,
            truncated_by: truncated.truncated_by,
            last_line_partial: truncated.last_line_partial == true
          }
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
