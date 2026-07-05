# frozen_string_literal: true

# 文件用途：文件变更队列，用于序列化文件操作
# 使用方法：通过 with_file_mutation_queue 方法确保同一文件的并发操作被序列化执行

module DeepForge
  module Adapters
    module Tool
      # 模块功能：文件变更队列，通过队列机制序列化文件操作，防止并发冲突
      module FileMutationQueue
        @queues = {}
        @registration_queue = Mutex.new
        @queues_mutex = Mutex.new

        class << self
          # 方法功能：在文件变更队列中序列化执行代码块
          # 参数：file_path - 文件路径，作为队列的键
          #       block - 要执行的代码块
          # 返回值：代码块的返回值
          def with_file_mutation_queue(file_path)
            key = get_mutation_queue_key(file_path)

            @queues_mutex.synchronize do
              @queues[key] ||= Queue.new
              queue = @queues[key]
              queue.push(:acquire)
            end

            begin
              yield
            ensure
              @queues_mutex.synchronize do
                queue = @queues[key]
                queue.pop if queue && !queue.empty?
                @queues.delete(key) if queue && queue.empty?
              end
            end
          end

          private

          # Get the mutation queue key for a file path.
          # @param file_path [String]
          # @return [String]
          def get_mutation_queue_key(file_path)
            resolved_path = File.expand_path(file_path)
            begin
              File.realpath(resolved_path)
            rescue Errno::ENOENT, Errno::ENOTDIR
              resolved_path
            end
          end
        end
      end
    end
  end
end
