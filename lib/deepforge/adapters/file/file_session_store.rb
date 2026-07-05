# frozen_string_literal: true

# 文件用途：基于文件的会话存储适配器
# 将会话数据以 JSONL 格式存储在文件系统中，每个线程对应独立的目录
# 包含事件文件(events.jsonl)、消息文件(messages.jsonl)和会话快照(session.json)
# 支持事件追加、消息追加、会话更新、数据压缩等功能
# 使用方法：FileSessionStore.new(data_dir: '/path/to/data')

require 'json'
require 'fileutils'
require 'time'

require_relative 'atomic_write'
require_relative 'agent_thread_store'

module DeepForge
  module Adapters
    module FileStore
      # 类功能：文件会话存储器
      # 以 JSONL 格式追加事件和消息到每个线程的文件中，
      # 同时维护一个 JSON 格式的会话快照文件
      class FileSessionStore
        # 常量：使用事件压缩前的最大文件大小（5MB）
        DEFAULT_USAGE_EVENT_COMPACTION_MAX_BYTES = 5 * 1024 * 1024
        # 常量：使用事件保留天数（365天）
        DEFAULT_USAGE_EVENT_RETENTION_DAYS = 365
        # 常量：每天的毫秒数
        MS_PER_DAY = 86_400_000

        # 方法功能：初始化文件会话存储器
        # 参数：data_dir - 会话存储的基础目录，usage_event_compaction - 使用事件压缩配置
        # 返回值：FileSessionStore 实例
        def initialize(data_dir:, usage_event_compaction: {})
          @data_dir = ::File.join(data_dir, 'threads')
          @usage_event_compaction = {
            max_bytes: [1, (usage_event_compaction[:max_bytes] || DEFAULT_USAGE_EVENT_COMPACTION_MAX_BYTES).to_i].max,
            retention_days: [1,
                             (usage_event_compaction[:retention_days] || DEFAULT_USAGE_EVENT_RETENTION_DAYS).to_i].max,
            now_iso: usage_event_compaction[:now_iso] || -> { Time.now.strftime('%FT%TZ') }
          }
        end

        # 方法功能：追加运行时事件到指定线程
        # 如果是使用事件且文件过大，会触发压缩
        # 参数：thread_id - 线程ID，event - 事件哈希
        # 返回值：无
        def append_event(thread_id, event)
          ensure_dir(thread_dir(thread_id))
          path = events_path(thread_id)
          ::File.open(path, 'a') { |f| f.puts(JSON.generate(event)) }
          compact_usage_events_if_large(thread_id) if event[:kind] == 'usage'
        end

        # 方法功能：追加对话轮次项到指定线程
        # 参数：thread_id - 线程ID，item - 对话轮次项哈希
        # 返回值：无
        def append_item(thread_id, item)
          ensure_dir(thread_dir(thread_id))
          path = messages_path(thread_id)
          ::File.open(path, 'a') { |f| f.puts(JSON.generate(item)) }
        end

        # 方法功能：重写指定线程的所有对话轮次项
        # 使用原子写入替换整个消息文件
        # 参数：thread_id - 线程ID，items - 对话轮次项数组
        # 返回值：无
        def rewrite_items(thread_id, items)
          ensure_dir(thread_dir(thread_id))
          contents = items.map { |item| JSON.generate(item) }.join("\n")
          AtomicWrite.write(messages_path(thread_id), contents.empty? ? '' : "#{contents}\n")
        end

        # 方法功能：更新指定线程中的对话轮次项
        # 找到匹配的项后合并补丁，并追加到消息文件
        # 参数：thread_id - 线程ID，item_id - 项ID，patch - 要应用的部分字段
        # 返回值：更新后的项哈希，未找到则返回 nil
        def update_item(thread_id, item_id, patch)
          items = load_items(thread_id)
          current = items.find { |item| item[:id] == item_id }
          return nil unless current

          updated = current.merge(patch)
          ensure_dir(thread_dir(thread_id))
          ::File.open(messages_path(thread_id), 'a') { |f| f.puts(JSON.generate(updated)) }
          updated
        end

        # 方法功能：加载指定线程自某个序列号之后的所有事件
        # 参数：thread_id - 线程ID，since_seq - 起始序列号
        # 返回值：事件数组，按序列号升序排列
        def load_events_since(thread_id, since_seq)
          all = DeepForge::Adapters::FileStore.read_jsonl(events_path(thread_id))
          all
            .select { |event| (event[:seq] || 0) > since_seq }
            .sort_by { |event| event[:seq] || 0 }
        end

        # 方法功能：加载指定线程的所有对话轮次项
        # 根据 ID 去重，保留每个项的最新版本
        # 参数：thread_id - 线程ID
        # 返回值：对话轮次项数组，按原始顺序排列
        def load_items(thread_id)
          raw = DeepForge::Adapters::FileStore.read_jsonl(messages_path(thread_id))
          latest_by_id = {}
          raw.each { |item| latest_by_id[item[:id]] = item }

          seen = {}
          ordered = []
          (raw.length - 1).downto(0) do |index|
            item = raw[index]
            next if seen[item[:id]]

            seen[item[:id]] = true
            ordered.unshift(latest_by_id[item[:id]])
          end
          ordered
        end

        # 方法功能：加载指定线程的会话记录
        # 参数：thread_id - 线程ID
        # 返回值：会话记录哈希，未找到或读取失败则返回 nil
        def load_session(thread_id)
          raw = ::File.read(session_path(thread_id))
          JSON.parse(raw, symbolize_names: true)
        rescue StandardError
          nil
        end

        # 方法功能：插入或更新会话记录
        # 使用原子写入将会话快照写入 session.json 文件
        # 参数：session - 会话记录哈希
        # 返回值：无
        def upsert_session(session)
          ensure_dir(thread_dir(session[:thread_id]))
          AtomicWrite.write(session_path(session[:thread_id]), JSON.generate(session))
        end

        # 方法功能：获取指定线程中事件的最大序列号
        # 参数：thread_id - 线程ID
        # 返回值：最大序列号整数
        def highest_seq(thread_id)
          events = DeepForge::Adapters::FileStore.read_jsonl(events_path(thread_id))
          events.reduce(0) { |max, event| [max, event[:seq] || 0].max }
        end

        # 方法功能：重置内存状态
        # 文件存储无内存状态，此方法为空操作
        # 返回值：无
        def reset_memory
          # 空操作，文件存储无需重置内存状态
        end

        # 方法功能：检查线程目录是否存在
        # 用于循环关闭时验证文件是否实际存在
        # 参数：thread_id - 线程ID
        # 返回值：目录存在返回 true，否则返回 false
        def exists?(thread_id)
          ::File.exist?(thread_dir(thread_id))
        rescue StandardError
          false
        end

        private

        # 方法功能：获取线程目录路径
        # 参数：thread_id - 线程ID
        # 返回值：线程目录的完整路径
        def thread_dir(thread_id)
          ::File.join(@data_dir, thread_id)
        end

        # 方法功能：获取事件文件路径
        # 参数：thread_id - 线程ID
        # 返回值：events.jsonl 文件的完整路径
        def events_path(thread_id)
          ::File.join(thread_dir(thread_id), 'events.jsonl')
        end

        # 方法功能：获取消息文件路径
        # 参数：thread_id - 线程ID
        # 返回值：messages.jsonl 文件的完整路径
        def messages_path(thread_id)
          ::File.join(thread_dir(thread_id), 'messages.jsonl')
        end

        # 方法功能：获取会话快照文件路径
        # 参数：thread_id - 线程ID
        # 返回值：session.json 文件的完整路径
        def session_path(thread_id)
          ::File.join(thread_dir(thread_id), 'session.json')
        end

        # 方法功能：确保目录存在，不存在则创建
        # 参数：path - 目录路径
        # 返回值：无
        def ensure_dir(path)
          FileUtils.mkdir_p(path)
        end

        # 方法功能：当使用事件文件过大时进行压缩
        # 检查文件大小是否超过阈值，超过则调用压缩方法
        # 参数：thread_id - 线程ID
        # 返回值：无
        def compact_usage_events_if_large(thread_id)
          path = events_path(thread_id)
          return unless ::File.exist?(path)

          size = ::File.size(path)
          return if size <= @usage_event_compaction[:max_bytes]

          events = DeepForge::Adapters::FileStore.read_jsonl(path)
          compacted = compact_usage_events(events, {
                                             now_iso: @usage_event_compaction[:now_iso].call,
                                             retention_days: @usage_event_compaction[:retention_days]
                                           })
          return if compacted.length >= events.length

          contents = compacted.map { |e| JSON.generate(e) }.join("\n")
          AtomicWrite.write(path, contents.empty? ? '' : "#{contents}\n")
        end

        # 方法功能：压缩使用事件
        # 根据保留策略删除过期事件，并合并同一时间段的事件
        # 参数：events - 事件数组，now_iso - 当前时间ISO字符串，retention_days - 保留天数
        # 返回值：压缩后的事件数组
        def compact_usage_events(events, now_iso:, retention_days:)
          cutoff_ms = (Time.parse(now_iso).to_i * 1000) - (retention_days * MS_PER_DAY)
          return events unless cutoff_ms.finite?

          latest_usage_index = -1
          latest_before_cutoff_index = -1
          events.each_with_index do |event, index|
            next unless event[:kind] == 'usage'

            latest_usage_index = index
            timestamp = begin
              Time.parse(event[:timestamp]).to_i * 1000
            rescue StandardError
              nil
            end
            latest_before_cutoff_index = index if timestamp && timestamp < cutoff_ms
          end
          return events if latest_usage_index.negative?

          keep = {}
          latest_usage_index_by_bucket = {}
          events.each_with_index do |event, index|
            if event[:kind] != 'usage'
              keep[index] = true
              next
            end

            next unless should_retain_usage_event(event, index, {
                                                    cutoff_ms: cutoff_ms,
                                                    latest_usage_index: latest_usage_index,
                                                    latest_before_cutoff_index: latest_before_cutoff_index
                                                  })

            bucket = usage_coalescing_bucket(event)
            previous = latest_usage_index_by_bucket[bucket]
            keep.delete(previous) if previous && previous != latest_before_cutoff_index
            keep[index] = true
            latest_usage_index_by_bucket[bucket] = index
          end

          events.select.each_with_index { |_event, index| keep[index] }
        end

        # 方法功能：判断使用事件是否应该保留
        # 基于时间戳和位置判断事件是否在保留期内
        # 参数：event - 事件哈希，index - 事件索引，cutoff_ms - 截止时间戳毫秒，
        #   latest_usage_index - 最后一个使用事件的索引，latest_before_cutoff_index - 截止时间前最后一个使用事件的索引
        # 返回值：应该保留返回 true，否则返回 false
        def should_retain_usage_event(event, index, cutoff_ms:, latest_usage_index:, latest_before_cutoff_index:)
          return true unless event[:kind] == 'usage'
          return true if index == latest_usage_index || index == latest_before_cutoff_index

          timestamp = begin
            Time.parse(event[:timestamp]).to_i * 1000
          rescue StandardError
            nil
          end
          return true unless timestamp

          timestamp >= cutoff_ms
        end

        # 方法功能：生成使用事件的合并桶标识
        # 用于将同一日期和模型的事件合并
        # 参数：event - 事件哈希
        # 返回值：格式为 "日期:模型" 的字符串
        def usage_coalescing_bucket(event)
          return '' unless event[:kind] == 'usage'

          timestamp = begin
            Time.parse(event[:timestamp])
          rescue StandardError
            nil
          end
          day = timestamp ? timestamp.strftime('%Y-%m-%d') : event[:timestamp]
          "#{day}:#{event[:model] || ''}"
        end
      end
    end
  end
end
