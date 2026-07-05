# frozen_string_literal: true

# 文件用途：内置工具的默认文件系统操作实现
# 使用方法：提供各工具所需的操作函数（读写、bash 执行、图片处理等）

require 'fileutils'
require 'tempfile'
require 'open3'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：为内置工具提供基于真实文件系统的默认操作实现
      module BuiltinToolOperations
        # 方法功能：根据 MIME 类型获取文件扩展名
        # 参数：mime_type - MIME 类型字符串（如 'image/png'）
        # 返回值：对应的文件扩展名字符串
        def self.image_extension(mime_type)
          case mime_type
          when 'image/png' then 'png'
          when 'image/jpeg' then 'jpg'
          when 'image/gif' then 'gif'
          when 'image/webp' then 'webp'
          else 'img'
          end
        end

        # 方法功能：使用 sips（macOS）缩放图片
        # 参数：buffer - 图片内容，mime_type - MIME 类型，options - 缩放选项
        # 返回值：ResizedImageResult 结构体或 nil
        def self.resize_image_with_sips(buffer, mime_type, options = ResizeImageOptions.new)
          sips = BuiltinToolUtils.resolve_executable(['/usr/bin/sips', 'sips'])
          return nil unless sips

          max_width = options.max_width || DEFAULT_IMAGE_MAX_DIMENSION
          max_height = options.max_height || DEFAULT_IMAGE_MAX_DIMENSION
          max_bytes = options.max_bytes || DEFAULT_IMAGE_MAX_BASE64_BYTES

          Dir.mktmpdir('deepforge-read-image-') do |temp_dir|
            input_path = File.join(temp_dir, "input.#{image_extension(mime_type)}")
            output_path = File.join(temp_dir, "output.#{image_extension(mime_type)}")

            begin
              File.binwrite(input_path, buffer)

              info = BuiltinToolUtils.spawn_capture(sips, ['-g', 'pixelWidth', '-g', 'pixelHeight', input_path],
                                                    cwd: temp_dir)
              width_match = info[:stdout].match(/pixelWidth:\s*(\d+)/)
              height_match = info[:stdout].match(/pixelHeight:\s*(\d+)/)
              original_width = width_match ? width_match[1].to_i : 0
              original_height = height_match ? height_match[1].to_i : 0

              original_base64 = [buffer].pack('m0')
              original_size = original_base64.bytesize

              if original_width.positive? && original_height.positive? &&
                 original_width <= max_width && original_height <= max_height &&
                 original_size < max_bytes
                return ResizedImageResult.new(
                  data_base64: original_base64,
                  mime_type: mime_type,
                  original_width: original_width,
                  original_height: original_height,
                  width: original_width,
                  height: original_height,
                  was_resized: false
                )
              end

              current_max = [max_width, max_height].max
              while current_max >= 1
                result = BuiltinToolUtils.spawn_capture(
                  sips,
                  ['--resampleHeightWidthMax', current_max.to_s, input_path, '--out', output_path],
                  cwd: temp_dir
                )
                return nil if result[:exit_code] != 0

                resized_buffer = File.binread(output_path)
                resized_base64 = [resized_buffer].pack('m0')
                resized_size = resized_base64.bytesize
                detected = BuiltinToolUtils.detect_image_mime_type(resized_buffer)

                resized_info = BuiltinToolUtils.spawn_capture(sips,
                                                              ['-g', 'pixelWidth', '-g', 'pixelHeight', output_path], cwd: temp_dir)
                resized_width = resized_info[:stdout].match(/pixelWidth:\s*(\d+)/)&.[](1).to_i
                resized_height = resized_info[:stdout].match(/pixelHeight:\s*(\d+)/)&.[](1).to_i

                if resized_size < max_bytes && resized_width.positive? && resized_height.positive?
                  return ResizedImageResult.new(
                    data_base64: resized_base64,
                    mime_type: detected&.mime_type || mime_type,
                    original_width: original_width,
                    original_height: original_height,
                    width: resized_width,
                    height: resized_height,
                    was_resized: resized_width != original_width || resized_height != original_height
                  )
                end

                current_max = (current_max * 0.75).to_i
              end

              nil
            rescue StandardError
              nil
            end
          end
        end

        # 方法功能：获取基于真实文件系统的默认读取操作
        # 返回值：ReadLocalToolOperations 结构体实例
        def self.default_read_local_tool_operations
          ReadLocalToolOperations.new(
            stat: ->(path) { File.lstat(path) },
            read_file: ->(path) { File.binread(path) },
            detect_image_mime_type: method(:detect_image_mime_type_from_buffer),
            resize_image: method(:resize_image_with_sips)
          )
        end

        # 方法功能：从缓冲区检测图片 MIME 类型（操作包装器）
        # 参数：buffer - 文件内容缓冲区
        # 返回值：ImageDetection 结构体或 nil
        def self.detect_image_mime_type_from_buffer(buffer)
          BuiltinToolUtils.detect_image_mime_type(buffer)
        end

        # 方法功能：使用真实进程创建 bash 操作
        # 返回值：BashLocalToolOperations 结构体实例
        def self.create_local_bash_operations
          BashLocalToolOperations.new(
            exec: lambda { |command, cwd, options|
              shell_config = BuiltinToolUtils.shell_config
              timed_out = false

              stdout_str = ''
              stderr_str = ''

              Open3.popen3(shell_config.shell, *shell_config.args, command,
                           chdir: cwd) do |stdin, stdout, stderr, wait_thr|
                stdin.close

                stdout_thread = Thread.new { stdout_str = stdout.read }
                stderr_thread = Thread.new { stderr_str = stderr.read }

                # Set up timeout
                timer = Thread.new do
                  sleep(options[:timeout_seconds])
                  timed_out = true
                  begin
                    Process.kill('TERM', wait_thr.pid)
                  rescue StandardError
                    nil
                  end
                end

                # Set up abort signal handler
                if options[:signal]
                  Thread.new do
                    options[:signal].wait
                    begin
                      Process.kill('TERM', wait_thr.pid)
                    rescue StandardError
                      nil
                    end
                  end
                end

                stdout_thread.join
                stderr_thread.join
                timer.kill if timer.alive?

                exit_code = wait_thr.value.exitstatus
                raise 'command aborted' if options[:signal]&.aborted?
                raise "command timed out after #{options[:timeout_seconds]} seconds" if timed_out

                { exit_code: exit_code }
              end
            }
          )
        end

        # 方法功能：获取基于真实文件系统的默认写入操作
        # 返回值：WriteLocalToolOperations 结构体实例
        def self.default_write_local_tool_operations
          WriteLocalToolOperations.new(
            mkdir: ->(path) { FileUtils.mkdir_p(path) },
            write_file: ->(path, content) { File.write(path, content) }
          )
        end

        # 方法功能：获取基于真实文件系统的默认编辑操作
        # 返回值：EditLocalToolOperations 结构体实例
        def self.default_edit_local_tool_operations
          EditLocalToolOperations.new(
            read_file: ->(path) { File.read(path) },
            write_file: ->(path, content) { File.write(path, content) }
          )
        end

        # 方法功能：获取默认的查找操作（空实现，使用外部 fd/rg）
        # 返回值：FindLocalToolOperations 结构体实例
        def self.default_find_local_tool_operations
          FindLocalToolOperations.new
        end

        # 方法功能：获取默认的搜索操作（空实现，使用外部 rg）
        # 返回值：GrepLocalToolOperations 结构体实例
        def self.default_grep_local_tool_operations
          GrepLocalToolOperations.new
        end

        # 方法功能：获取基于真实文件系统的默认列表操作
        # 返回值：LsLocalToolOperations 结构体实例
        def self.default_ls_local_tool_operations
          LsLocalToolOperations.new(
            stat: ->(path) { File.lstat(path) },
            readdir: lambda { |path|
              Dir.entries(path).select do |name|
                name != '.' && name != '..'
              end.map { |name| { name: name } }
            }
          )
        end
      end
    end
  end
end
