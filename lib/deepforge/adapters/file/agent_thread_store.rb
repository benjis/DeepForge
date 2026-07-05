# frozen_string_literal: true

# 文件用途：基于文件的线程存储适配器
# 将线程数据以 JSON 文件格式存储在文件系统中，通过原子重命名确保写入安全
# 维护一个紧凑的 index.json 索引文件，使 list 操作更高效
# 目录结构：
#   {dataDir}/threads/index.json - 线程索引
#   {dataDir}/threads/{threadId}/thread.json - 线程详情
#   {dataDir}/threads/{threadId}/messages.jsonl - 消息记录
#   {dataDir}/threads/{threadId}/events.jsonl - 事件记录
# 使用方法：AgentThreadStore.new(data_dir: '/path/to/data')

require 'json'
require 'fileutils'
require 'securerandom'

require_relative 'atomic_write'

module DeepForge
  module Adapters
    module FileStore
      # 类功能：文件线程存储器
      # 将线程状态以 JSON 文件存储，通过原子重命名保证写入安全
      class AgentThreadStore
        # 方法功能：初始化文件线程存储器
        # 参数：data_dir - 线程存储的基础目录，now - 可选的时钟函数
        # 返回值：AgentThreadStore 实例
        def initialize(data_dir:, now: nil)
          @data_dir = ::File.join(data_dir, 'threads')
          @now = now || -> { Time.now }
          @index_mutex = Mutex.new
          @index_queue = Queue.new
        end

        # 方法功能：列出所有线程摘要
        # 从索引文件读取线程ID列表，然后读取每个线程的详情文件
        # 参数：options - 可选的过滤选项（limit、search、includeArchived）
        # 返回值：线程摘要数组，按更新时间降序排列
        def list(_options = {})
          ensure_dir(@data_dir)
          index = read_index
          summaries = []
          index[:order].each do |thread_id|
            path = thread_file_path(thread_id)
            begin
              raw = ::File.read(path)
              thread = JSON.parse(raw, symbolize_names: true)
              summaries << to_thread_summary(thread)
            rescue StandardError
              # Skip broken entries rather than failing the whole list.
            end
          end
          summaries.sort_by { |s| -s[:updated_at].to_s.to_i }
        end

        # 方法功能：获取指定线程的详情
        # 参数：thread_id - 线程ID
        # 返回值：线程记录哈希，未找到则返回 nil
        def get(thread_id)
          raw = ::File.read(thread_file_path(thread_id))
          JSON.parse(raw, symbolize_names: true)
        rescue StandardError
          nil
        end

        # 方法功能：插入或更新线程记录
        # 使用原子写入将线程数据写入 thread.json，并更新索引
        # 参数：thread - 线程记录哈希
        # 返回值：插入或更新后的线程记录
        def upsert(thread)
          ensure_dir(thread_dir(thread[:id]))
          path = thread_file_path(thread[:id])
          AtomicWrite.write(path, JSON.generate(thread))
          update_index do |current|
            order = current[:order] | [thread[:id]]
            { order: order, updated_at: @now.call.strftime('%FT%TZ') }
          end
          thread
        end

        # 方法功能：删除指定线程
        # 删除线程目录并从索引中移除
        # 参数：thread_id - 线程ID
        # 返回值：删除成功返回 true，未找到返回 false
        def delete(thread_id)
          dir = thread_dir(thread_id)
          return false unless ::File.exist?(dir)

          FileUtils.rm_rf(dir)
          update_index do |current|
            order = current[:order].reject { |id| id == thread_id }
            { order: order, updated_at: @now.call.strftime('%FT%TZ') }
          end
          true
        end

        private

        # 方法功能：读取线程索引
        # 从 index.json 文件解析索引数据
        # 返回值：包含 :order（线程ID数组）和 :updated_at（更新时间）的哈希
        def read_index
          raw = ::File.read(index_path)
          parsed = JSON.parse(raw, symbolize_names: true)
          {
            order: parsed[:order].is_a?(Array) ? parsed[:order] : [],
            updated_at: parsed[:updated_at] || @now.call.strftime('%FT%TZ')
          }
        rescue StandardError
          { order: [], updated_at: @now.call.strftime('%FT%TZ') }
        end

        # 方法功能：更新线程索引
        # 使用互斥锁保护并发访问，通过块函数修改索引后原子写入
        # 参数：block - 接收当前索引并返回新索引的代码块
        # 返回值：无
        def update_index(&block)
          @index_mutex.synchronize do
            current = read_index
            next_val = block.call(current)
            ensure_dir(@data_dir)
            AtomicWrite.write(index_path, JSON.generate(next_val))
          end
        end

        # 方法功能：获取线程目录路径
        # 参数：thread_id - 线程ID
        # 返回值：线程目录的完整路径
        def thread_dir(thread_id)
          ::File.join(@data_dir, thread_id)
        end

        # 方法功能：获取线程详情文件路径
        # 参数：thread_id - 线程ID
        # 返回值：thread.json 文件的完整路径
        def thread_file_path(thread_id)
          ::File.join(thread_dir(thread_id), 'thread.json')
        end

        # 方法功能：获取索引文件路径
        # 返回值：index.json 文件的完整路径
        def index_path
          ::File.join(@data_dir, 'index.json')
        end

        # 方法功能：确保目录存在，不存在则创建
        # 参数：path - 目录路径
        # 返回值：无
        def ensure_dir(path)
          FileUtils.mkdir_p(path)
        end

        # 方法功能：将线程记录转换为线程摘要
        # 提取关键字段用于列表显示
        # 参数：thread - 线程记录哈希
        # 返回值：线程摘要哈希
        def to_thread_summary(thread)
          {
            id: thread[:id],
            title: thread[:title],
            model: thread[:model],
            created_at: thread[:created_at],
            updated_at: thread[:updated_at]
          }
        end
      end

      # 方法功能：读取 JSONL 文件内容
      # 解析 JSONL 格式文件，跳过空行和格式错误的行
      # 参数：path - JSONL 文件路径
      # 返回值：解析后的 JSON 对象数组
      def self.read_jsonl(path)
        content = ::File.read(path)
        out = []
        content.each_line do |line|
          trimmed = line.strip
          next if trimmed.empty?

          begin
            out << JSON.parse(trimmed, symbolize_names: true)
          rescue JSON::ParserError
            # 跳过格式错误的行，避免单个坏记录影响整个重放
          end
        end
        out
      rescue StandardError
        []
      end
    end
  end
end
