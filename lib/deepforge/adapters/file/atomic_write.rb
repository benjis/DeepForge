# frozen_string_literal: true

# 文件用途：原子写入工具模块
# 提供文件原子写入功能，通过先写入临时文件再重命名的方式，
# 确保目标文件不会处于不完整的中间状态
# 使用方法：调用 AtomicWrite.write(path, contents) 原子写入文件，
# 或使用 AtomicWrite.with_temp(path) { |tmp| ... } 进行自定义临时文件操作

require 'tempfile'
require 'fileutils'
require 'digest'

module DeepForge
  module Adapters
    module FileStore
      # 类功能：原子文件写入器
      # 通过临时文件+重命名的方式实现原子写入，保证数据一致性
      class AtomicWrite
        # 方法功能：原子写入内容到文件
        # 先创建临时文件，写入内容后重命名为目标文件
        # 参数：path - 目标文件路径，contents - 要写入的内容
        # 返回值：无
        # 异常：写入或重命名失败时抛出 StandardError
        # @param path [String] the target file path
        # @param contents [String] the content to write
        # @raise [StandardError] if writing or renaming fails
        def self.write(path, contents)
          dir = ::File.dirname(path)
          FileUtils.mkdir_p(dir)

          tmp = "#{path}.#{Process.pid}.#{Time.now.to_i}.#{SecureRandom.uuid}.tmp"
          begin
            ::File.write(tmp, contents)
            ::File.rename(tmp, path)
          rescue StandardError => e
            begin
              ::File.delete(tmp)
            rescue Errno::ENOENT
              # 如果临时文件不存在则忽略
            end
            raise e
          end
        end

        # 方法功能：使用临时文件进行自定义写入操作
        # 创建临时文件后将其路径传递给块，块执行完毕后重命名为目标文件
        # 参数：path - 目标文件路径，block - 接收临时文件路径的代码块
        # 返回值：无
        def self.with_temp(path, &)
          dir = ::File.dirname(path)
          FileUtils.mkdir_p(dir)

          tmp = "#{path}.#{Process.pid}.#{Time.now.to_i}.#{SecureRandom.uuid}.tmp"
          begin
            yield tmp
            ::File.rename(tmp, path)
          rescue StandardError => e
            begin
              ::File.delete(tmp)
            rescue Errno::ENOENT
              # ignore
            end
            raise e
          end
        end
      end
    end
  end
end
