# frozen_string_literal: true

# 文件用途：混合模式线程存储适配器
# 结合 JSONL 文件存储和 SQLite 索引，提供高效的线程存储和查询功能
# JSONL 文件是权威数据源，SQLite 是可重建的索引
# 使用方法：AgentThreadStore.new(data_dir: '/path')

require 'json'
require 'fileutils'
require 'sqlite3'
require 'securerandom'

require_relative '../file/agent_thread_store'

module DeepForge
  module Adapters
    module Hybrid
      # 类功能：混合模式线程存储器
      # 使用 JSONL 文件存储线程数据，SQLite 作为可重建的索引
      class AgentThreadStore
        # 方法功能：初始化混合模式线程存储器
        # 创建数据目录、初始化 SQLite 数据库、执行迁移和数据回填
        # 参数：data_dir - 数据目录，sqlite_path - SQLite数据库路径，now_iso - 时间函数
        # 返回值：AgentThreadStore 实例
        def initialize(data_dir:, sqlite_path: nil, now_iso: nil)
          @data_dir = ::File.join(data_dir, 'threads')
          @sqlite_path = sqlite_path || ::File.join(data_dir, 'index.sqlite3')
          @now_iso = now_iso || -> { Time.now.utc.strftime('%FT%TZ') }
          @db = nil
          @metadata_queues = {}
          @metadata_mutexes = {}
          @ready = false
          initialize_store
        end

        # 方法功能：标记存储器就绪
        # 返回值：无
        def ready; end

        # 方法功能：关闭存储器，释放数据库连接
        # 返回值：无
        def close
          @db&.close
        ensure
          @db = nil
        end

        # 方法功能：列出所有线程摘要
        # 优先从 SQLite 索引查询，失败则回退到文件系统遍历
        # 参数：options - 可选的过滤选项
        # 返回值：线程摘要数组（camelCase 格式）
        def list(options = {})
          ready
          result = if @db
                     rows = query_thread_rows(options)
                     summaries = rows.filter_map { |row| summary_from_row(row) if row_has_readable_jsonl?(row) }
                     summaries.any? || options.any? ? summaries : filter_thread_summaries(list_from_filesystem, options)
                   else
                     filter_thread_summaries(list_from_filesystem, options)
                   end
          camel_case_keys(result)
        rescue StandardError => e
          warn_sqlite('list', e)
          camel_case_keys(filter_thread_summaries(list_from_filesystem, options))
        end

        # 方法功能：获取指定线程的详情
        # 从磁盘读取线程数据并转换为 camelCase 格式
        # 参数：thread_id - 线程ID
        # 返回值：线程记录哈希（camelCase），未找到则返回 nil
        def get(thread_id)
          ready
          read_thread_from_disk(thread_id)
        end

        # 方法功能：插入或更新线程记录
        # 追加元数据到文件，同时更新 SQLite 索引
        # 参数：thread - 线程记录哈希
        # 返回值：原始线程记录
        def upsert(thread)
          ready
          # 确保线程使用符号键以供内部方法使用
          sym_thread = thread.is_a?(Hash) ? symbolize_keys(thread) : thread
          append_metadata(sym_thread)
          upsert_index_best_effort(index_record_for_thread(sym_thread)) if @db
          thread
        end

        # 方法功能：删除指定线程
        # 删除 SQLite 索引行和文件系统中的线程目录
        # 参数：thread_id - 线程ID
        # 返回值：删除始终返回 true
        def delete(thread_id)
          ready
          delete_index_row(thread_id) if @db
          thread_dir = ::File.join(@data_dir, thread_id)
          FileUtils.rm_rf(thread_dir)
          true
        end

        # 方法功能：更新 SQLite 中的事件序列号高水位
        # 用于跟踪每个线程的最新事件序列号
        # 参数：thread_id - 线程ID，seq - 事件序列号
        # 返回值：无
        def note_event_seq(thread_id, seq)
          return unless @db

          @db.execute('UPDATE threads SET event_seq_high_water = MAX(event_seq_high_water, ?) WHERE id = ?',
                      [seq, thread_id])
        rescue StandardError => e
          warn_sqlite('note_event_seq', e)
        end

        private

        # 方法功能：将哈希键从 snake_case 转换为 camelCase
        # 确保 Ruby 后端返回与 TypeScript 版本相同的键格式
        # 参数：obj - 要转换的哈希或数组
        # 返回值：转换后的对象
        def camel_case_keys(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(k, v), h|
              camel_key = k.to_s.gsub(/_([a-z0-9])/) { |m| m[1].upcase }
              h[camel_key] = camel_case_keys(v)
            end
          when Array
            obj.map { |item| camel_case_keys(item) }
          else
            obj
          end
        end

        # 方法功能：输出 SQLite 错误警告
        # 参数：context - 操作上下文，error - 错误对象
        # 返回值：无
        def warn_sqlite(context, error)
          warn "[AgentThreadStore] SQLite #{context} failed: #{error.message}"
        end

        # 方法功能：在表中添加缺失的列
        # 检查列是否存在，不存在则添加
        # 参数：db - SQLite数据库，table - 表名，column_def - 列定义
        # 返回值：无
        def add_column_if_missing(db, table, column_def)
          column_name = column_def.split.first
          columns = db.execute("PRAGMA table_info(#{table})").map { |row| row[1] }
          return if columns.include?(column_name)

          db.execute("ALTER TABLE #{table} ADD COLUMN #{column_def}")
        rescue StandardError => e
          warn "[AgentThreadStore] add_column_if_missing: #{e.message}"
        end

        # 方法功能：初始化存储器
        # 创建目录、打开 SQLite 数据库、执行迁移和数据回填
        # 返回值：无
        def initialize_store
          FileUtils.mkdir_p(@data_dir)
          FileUtils.mkdir_p(::File.dirname(@sqlite_path))
          @db = SQLite3::Database.new(@sqlite_path)
          @db.execute('PRAGMA journal_mode = WAL')
          @db.execute('PRAGMA foreign_keys = ON')
          @db.results_as_hash = true
          migrate
          backfill
          @ready = true
        rescue StandardError => e
          warn_sqlite('initialize', e)
          begin
            @db&.close
          rescue StandardError
            nil
          end
          @db = nil
          @ready = true
        end

        # 方法功能：执行数据库迁移
        # 创建 threads 表和索引（如果不存在）
        # 返回值：无
        def migrate
          return unless @db

          @db.execute_batch(<<~SQL)
            CREATE TABLE IF NOT EXISTS threads (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              workspace TEXT NOT NULL,
              model TEXT NOT NULL,
              mode TEXT NOT NULL,
              status TEXT NOT NULL,
              approval_policy TEXT NOT NULL,
              sandbox_mode TEXT NOT NULL,
              cost_budget_usd REAL,
              cost_budget_warning_sent INTEGER,
              relation TEXT NOT NULL,
              parent_thread_id TEXT,
              forked_from_thread_id TEXT,
              forked_from_title TEXT,
              forked_at TEXT,
              forked_from_message_count INTEGER,
              forked_from_turn_count INTEGER,
              goal_json TEXT,
              todos_json TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              preview TEXT,
              message_count INTEGER NOT NULL DEFAULT 0,
              event_seq_high_water INTEGER NOT NULL DEFAULT 0,
              metadata_path TEXT NOT NULL,
              messages_path TEXT NOT NULL,
              events_path TEXT NOT NULL,
              search_text TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS threads_updated_idx ON threads(updated_at_ms DESC, id DESC);
          SQL
        end

        # 方法功能：回填数据到 SQLite 索引
        # 遍历文件系统中的所有线程，将其信息写入索引
        # 返回值：无
        def backfill
          return unless @db

          thread_ids_from_filesystem.each do |thread_id|
            thread = read_thread_from_disk(thread_id)
            next unless thread

            upsert_index_best_effort(index_record_for_thread(thread))
          end
        end

        # 方法功能：获取线程目录路径
        # 参数：thread_id - 线程ID
        # 返回值：线程目录的完整路径
        def thread_dir(thread_id)
          ::File.join(@data_dir, thread_id)
        end

        # 方法功能：获取元数据文件路径
        # 参数：thread_id - 线程ID
        # 返回值：metadata.jsonl 文件的完整路径
        def metadata_path(thread_id)
          ::File.join(thread_dir(thread_id), 'metadata.jsonl')
        end

        # 方法功能：获取消息文件路径
        # 参数：thread_id - 线程ID
        # 返回值：messages.jsonl 文件的完整路径
        def messages_path(thread_id)
          ::File.join(thread_dir(thread_id), 'messages.jsonl')
        end

        # 方法功能：获取事件文件路径
        # 参数：thread_id - 线程ID
        # 返回值：events.jsonl 文件的完整路径
        def events_path(thread_id)
          ::File.join(thread_dir(thread_id), 'events.jsonl')
        end

        # 方法功能：从文件系统获取所有线程ID
        # 遍历数据目录，列出所有子目录作为线程ID
        # 返回值：线程ID数组
        def thread_ids_from_filesystem
          return [] unless ::File.directory?(@data_dir)

          Dir.children(@data_dir).select { |d| ::File.directory?(::File.join(@data_dir, d)) }
        rescue StandardError
          []
        end

        # 方法功能：从文件系统列出所有线程
        # 读取每个线程的元数据和消息，构建完整线程记录
        # 返回值：线程记录数组
        def list_from_filesystem
          thread_ids_from_filesystem.filter_map { |tid| read_thread_from_disk(tid) }
        end

        # 方法功能：从磁盘读取线程数据
        # 解析元数据和消息文件，构建完整的线程记录
        # 参数：thread_id - 线程ID
        # 返回值：线程记录哈希，读取失败则返回 nil
        def read_thread_from_disk(thread_id)
          thread_dir(thread_id)
          meta_file = metadata_path(thread_id)
          return nil unless ::File.exist?(meta_file)

          entries = ::File.readlines(meta_file).filter_map do |line|
            JSON.parse(line)
          rescue StandardError
            nil
          end
          thread = entries.reverse_each.find { |e| e['kind'] == 'thread_metadata' }&.dig('thread')
          return nil unless thread

          items_file = messages_path(thread_id)
          if ::File.exist?(items_file)
            items = ::File.readlines(items_file).filter_map do |line|
              JSON.parse(line)
            rescue StandardError
              nil
            end
            thread = hydrate_thread_items(thread, items)
          end

          symbolize_keys(thread)
        rescue StandardError => e
          warn "[AgentThreadStore] read_thread_from_disk #{thread_id}: #{e.message}"
          nil
        end

        # 方法功能：追加线程元数据到 JSONL 文件
        # 将线程元数据（不含消息内容）追加到 metadata.jsonl
        # 参数：thread - 线程记录哈希
        # 返回值：无
        def append_metadata(thread)
          dir = thread_dir(thread[:id])
          FileUtils.mkdir_p(dir)
          line = { kind: 'thread_metadata', version: 1, timestamp: @now_iso.call,
                   thread: strip_thread_item_bodies(thread) }
          append_jsonl_line(metadata_path(thread[:id]), line)
        end

        # 方法功能：追加一行 JSON 到文件
        # 参数：path - 文件路径，value - 要写入的值
        # 返回值：无
        def append_jsonl_line(path, value)
          ::File.open(path, 'a') { |f| f.puts(JSON.generate(value)) }
        end

        # 方法功能：剥离线程中的消息内容
        # 清空轮次的提示词和项目，仅保留元数据
        # 参数：thread - 线程记录哈希
        # 返回值：剥离后的新哈希
        def strip_thread_item_bodies(thread)
          thread.merge(
            turns: (thread[:turns] || []).map { |t| t.merge(prompt: '', items: []) }
          )
        end

        # 方法功能：为线程填充消息内容
        # 从消息文件读取项，按轮次分组并填充到线程记录中
        # 参数：thread - 线程记录哈希，items - 消息项数组，options - 选项
        # 返回值：填充后的线程记录哈希
        def hydrate_thread_items(thread, items = [], options = {})
          return strip_thread_item_bodies(thread) if items.empty? && !options[:preserveExistingItemsWhenNoFileItems]

          items_by_turn = {}
          items.each do |item|
            tid = item['turnId'] || item[:turn_id]
            next unless tid

            (items_by_turn[tid] ||= []) << item
          end

          known_turn_ids = (thread[:turns] || []).map { |t| t[:id] || t['id'] }.compact
          turns = (thread[:turns] || []).map do |turn|
            tid = turn[:id] || turn['id']
            turn_items = items_by_turn[tid] || []
            turn.merge(
              prompt: prompt_from_items(turn_items) || turn[:prompt] || '',
              attachment_ids: attachment_ids_from_items(turn_items),
              items: turn_items
            )
          end

          items_by_turn.each do |tid, turn_items|
            next if known_turn_ids.include?(tid)

            turns << turn_from_items(thread[:id], tid, turn_items, thread[:updated_at])
          end

          thread.merge(turns: turns)
        end

        # 方法功能：从消息项构建轮次记录
        # 参数：thread_id - 线程ID，turn_id - 轮次ID，items - 消息项数组，fallback_time - 备用时间
        # 返回值：轮次记录哈希
        def turn_from_items(thread_id, turn_id, items, fallback_time)
          {
            id: turn_id, thread_id: thread_id, status: 'completed',
            prompt: prompt_from_items(items) || '',
            steering: [], attachment_ids: attachment_ids_from_items(items),
            active_skill_ids: [], injected_memory_ids: [],
            created_at: items.first&.dig('createdAt') || fallback_time,
            finished_at: items.last&.dig('finishedAt') || fallback_time,
            items: items
          }
        end

        # 方法功能：从消息项中提取用户提示词
        # 查找 kind 为 'user_message' 的项并返回其文本
        # 参数：items - 消息项数组
        # 返回值：用户提示词字符串，未找到则返回 nil
        def prompt_from_items(items)
          items.each do |item|
            kind = item['kind'] || item[:kind]
            return item['text'] || item[:text] if kind == 'user_message'
          end
          nil
        end

        # 方法功能：从消息项中提取附件ID列表
        # 从所有用户消息项中收集附件ID并去重
        # 参数：items - 消息项数组
        # 返回值：附件ID数组
        def attachment_ids_from_items(items)
          items.filter_map do |item|
            next unless (item['kind'] || item[:kind]) == 'user_message'

            (item['attachment_ids'] || item[:attachment_ids] || []).select { |id| id.is_a?(String) && !id.strip.empty? }
          end.flatten.uniq
        end

        # 方法功能：将哈希键转换为符号
        # 递归转换所有键为符号格式
        # 参数：hash - 要转换的哈希
        # 返回值：转换后的新哈希
        def symbolize_keys(hash)
          hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v.is_a?(Hash) ? symbolize_keys(v) : v }
        end

        # 方法功能：从 SQLite 查询线程行
        # 根据过滤选项构建 SQL 查询并执行
        # 参数：options - 过滤选项（status、limit等）
        # 返回值：线程行数组
        def query_thread_rows(options)
          conditions = ['1=1']
          params = []
          if options[:status]
            conditions << 'status = ?'
            params << options[:status]
          end
          sql = "SELECT * FROM threads WHERE #{conditions.join(' AND ')} ORDER BY updated_at_ms DESC, id DESC"
          sql += " LIMIT #{options[:limit].to_i}" if options[:limit]&.positive?
          @db.execute(sql, params)
        rescue StandardError => e
          warn_sqlite('query_thread_rows', e)
          []
        end

        # 方法功能：在 SQLite 中查找指定线程
        # 参数：thread_id - 线程ID
        # 返回值：线程行，未找到则返回 nil
        def find_row(thread_id)
          rows = @db.execute('SELECT * FROM threads WHERE id = ?', [thread_id])
          rows.first
        rescue StandardError
          nil
        end

        # 方法功能：检查行对应的 JSONL 文件是否存在
        # 参数：row - 数据库行
        # 返回值：文件存在返回 true，否则返回 false
        def row_has_readable_jsonl?(row)
          ::File.exist?(row['metadata_path'])
        end

        # 方法功能：从数据库行构建线程摘要
        # 将数据库行转换为线程摘要哈希格式
        # 参数：row - 数据库行
        # 返回值：线程摘要哈希
        def summary_from_row(row)
          {
            id: row['id'], title: row['title'], workspace: row['workspace'],
            model: row['model'], mode: row['mode'], status: row['status'],
            approval_policy: row['approval_policy'], sandbox_mode: row['sandbox_mode'],
            cost_budget_usd: row['cost_budget_usd'],
            cost_budget_warning_sent: row['cost_budget_warning_sent'] == 1,
            relation: row['relation'],
            parent_thread_id: row['parent_thread_id'],
            forked_from_thread_id: row['forked_from_thread_id'],
            forked_from_title: row['forked_from_title'],
            forked_at: row['forked_at'],
            forked_from_message_count: row['forked_from_message_count'],
            forked_from_turn_count: row['forked_from_turn_count'],
            goal: if row['goal_json']
                    begin
                      JSON.parse(row['goal_json'])
                    rescue StandardError
                      nil
                    end
                  end,
            todos: if row['todos_json']
                     begin
                       JSON.parse(row['todos_json'])
                     rescue StandardError
                       nil
                     end
                   end,
            created_at: row['created_at'], updated_at: row['updated_at']
          }
        end

        # 方法功能：从线程记录构建索引记录
        # 将线程记录转换为适合插入 SQLite 的格式
        # 参数：thread - 线程记录哈希
        # 返回值：索引记录哈希
        def index_record_for_thread(thread)
          # Helper to get value with snake_case or camelCase key
          get = ->(snake, camel = nil) { thread[snake] || thread[camel] }
          goal_json = get.call(:goal) ? JSON.generate(get.call(:goal)) : nil
          todos_json = get.call(:todos) ? JSON.generate(get.call(:todos)) : nil
          now_ms = (Time.now.utc.to_f * 1000).to_i
          {
            id: get.call(:id), title: get.call(:title), workspace: get.call(:workspace),
            model: get.call(:model), mode: get.call(:mode, :mode) || 'agent',
            status: get.call(:status) || 'idle',
            approval_policy: get.call(:approval_policy, :approvalPolicy) || 'on-request',
            sandbox_mode: get.call(:sandbox_mode, :sandboxMode) || 'workspace-write',
            cost_budget_usd: get.call(:cost_budget_usd, :costBudgetUsd),
            cost_budget_warning_sent: (get.call(:cost_budget_warning_sent, :costBudgetWarningSent) ? 1 : 0),
            relation: get.call(:relation) || 'primary',
            parent_thread_id: get.call(:parent_thread_id, :parentThreadId),
            forked_from_thread_id: get.call(:forked_from_thread_id, :forkedFromThreadId),
            forked_from_title: get.call(:forked_from_title, :forkedFromTitle),
            forked_at: get.call(:forked_at, :forkedAt),
            forked_from_message_count: get.call(:forked_from_message_count, :forkedFromMessageCount),
            forked_from_turn_count: get.call(:forked_from_turn_count, :forkedFromTurnCount),
            goal_json: goal_json, todos_json: todos_json,
            created_at: get.call(:created_at, :createdAt) || @now_iso.call,
            updated_at: get.call(:updated_at, :updatedAt) || @now_iso.call,
            created_at_ms: now_ms, updated_at_ms: now_ms,
            preview: '', message_count: 0, event_seq_high_water: 0,
            metadata_path: metadata_path(thread[:id]),
            messages_path: messages_path(thread[:id]),
            events_path: events_path(thread[:id]),
            search_text: "#{thread[:title]} #{thread[:workspace]}"
          }
        end

        # 方法功能：尽力插入或更新 SQLite 索引记录
        # 使用 INSERT OR REPLACE 语句更新索引
        # 参数：record - 索引记录哈希
        # 返回值：无
        def upsert_index_best_effort(record)
          return unless @db

          params = record.values_at(
            :id, :title, :workspace, :model, :mode, :status,
            :approval_policy, :sandbox_mode, :cost_budget_usd, :cost_budget_warning_sent,
            :relation, :parent_thread_id, :forked_from_thread_id, :forked_from_title,
            :forked_at, :forked_from_message_count, :forked_from_turn_count,
            :goal_json, :todos_json, :created_at, :updated_at,
            :created_at_ms, :updated_at_ms, :preview, :message_count,
            :event_seq_high_water, :metadata_path, :messages_path, :events_path, :search_text
          )
          sql = 'INSERT OR REPLACE INTO threads (id, title, workspace, model, mode, status, approval_policy, sandbox_mode, cost_budget_usd, cost_budget_warning_sent, relation, parent_thread_id, forked_from_thread_id, forked_from_title, forked_at, forked_from_message_count, forked_from_turn_count, goal_json, todos_json, created_at, updated_at, created_at_ms, updated_at_ms, preview, message_count, event_seq_high_water, metadata_path, messages_path, events_path, search_text) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
          @db.execute(sql, params)
        rescue StandardError => e
          warn_sqlite('upsert_index', e)
        end

        # 方法功能：删除 SQLite 中的索引行
        # 参数：thread_id - 线程ID
        # 返回值：无
        def delete_index_row(thread_id)
          return unless @db

          @db.execute('DELETE FROM threads WHERE id = ?', [thread_id])
        rescue StandardError => e
          warn_sqlite('delete_index', e)
        end

        # 方法功能：过滤线程摘要
        # 根据状态、搜索关键词和限制数量过滤线程列表
        # 参数：threads - 线程摘要数组，options - 过滤选项
        # 返回值：过滤后的线程摘要数组
        def filter_thread_summaries(threads, options)
          result = threads
          result = result.select { |t| t[:status] == options[:status] } if options[:status]
          if options[:search]
            q = options[:search].downcase
            result = result.select do |t|
              (t[:title] || '').downcase.include?(q) || (t[:workspace] || '').downcase.include?(q)
            end
          end
          result = result.first(options[:limit]) if options[:limit]&.positive?
          result
        end
      end
    end
  end
end
