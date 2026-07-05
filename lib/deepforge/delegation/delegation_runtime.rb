# frozen_string_literal: true

# 文件用途：委托运行时管理模块
# 使用方法：管理子代理的执行、记录和聚合统计，
#           支持子运行记录的持久化和诊断信息查询。

require 'json'
require 'fileutils'

module DeepForge
  module Delegation
    # 子运行使用量统计结构体
    ChildRunUsage = Struct.new(
      :prompt_tokens, :completion_tokens, :total_tokens,
      :cached_tokens, :cache_hit_tokens, :cache_miss_tokens,
      :cache_hit_rate, :turns,
      :cost_usd, :cost_cny,
      :cache_savings_usd, :cache_savings_cny,
      :token_economy_savings_tokens, :token_economy_savings_usd, :token_economy_savings_cny,
      keyword_init: true
    ) do
      # 方法功能：创建默认的使用量统计（所有值为 0 或 nil）
      # 返回值：ChildRunUsage - 默认使用量统计对象
      def self.default
        new(
          prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
          cached_tokens: nil, cache_hit_tokens: nil, cache_miss_tokens: nil,
          cache_hit_rate: nil, turns: nil,
          cost_usd: nil, cost_cny: nil,
          cache_savings_usd: nil, cache_savings_cny: nil,
          token_economy_savings_tokens: nil, token_economy_savings_usd: nil, token_economy_savings_cny: nil
        )
      end
    end

    # 子代理运行记录结构体
    ChildRunRecord = Struct.new(
      :id, :parent_thread_id, :parent_turn_id, :label,
      :prompt, :workspace, :model,
      :status, :summary, :error, :usage,
      :created_at, :updated_at,
      keyword_init: true
    ) do
      # 方法功能：从哈希创建子运行记录
      # 参数：attrs - 包含记录属性的哈希
      # 返回值：ChildRunRecord - 子运行记录对象
      def self.from_hash(attrs)
        usage_attrs = attrs[:usage] || {}
        usage = ChildRunUsage.new(
          prompt_tokens: usage_attrs[:prompt_tokens] || 0,
          completion_tokens: usage_attrs[:completion_tokens] || 0,
          total_tokens: usage_attrs[:total_tokens] || 0,
          cached_tokens: usage_attrs[:cached_tokens],
          cache_hit_tokens: usage_attrs[:cache_hit_tokens],
          cache_miss_tokens: usage_attrs[:cache_miss_tokens],
          cache_hit_rate: usage_attrs[:cache_hit_rate],
          turns: usage_attrs[:turns],
          cost_usd: usage_attrs[:cost_usd],
          cost_cny: usage_attrs[:cost_cny],
          cache_savings_usd: usage_attrs[:cache_savings_usd],
          cache_savings_cny: usage_attrs[:cache_savings_cny],
          token_economy_savings_tokens: usage_attrs[:token_economy_savings_tokens],
          token_economy_savings_usd: usage_attrs[:token_economy_savings_usd],
          token_economy_savings_cny: usage_attrs[:token_economy_savings_cny]
        )
        new(
          id: attrs[:id],
          parent_thread_id: attrs[:parent_thread_id],
          parent_turn_id: attrs[:parent_turn_id],
          label: attrs[:label],
          prompt: attrs[:prompt],
          workspace: attrs[:workspace],
          model: attrs[:model],
          status: attrs[:status],
          summary: attrs[:summary],
          error: attrs[:error],
          usage: usage,
          created_at: attrs[:created_at],
          updated_at: attrs[:updated_at]
        )
      end

      # 方法功能：将记录转换为哈希
      # 返回值：Hash - 记录的哈希表示
      def to_hash
        {
          id: id,
          parent_thread_id: parent_thread_id,
          parent_turn_id: parent_turn_id,
          label: label,
          prompt: prompt,
          workspace: workspace,
          model: model,
          status: status,
          summary: summary,
          error: error,
          usage: usage ? usage.to_h.transform_keys { |k| k.to_s.gsub('_', '').to_sym } : nil,
          created_at: created_at,
          updated_at: updated_at
        }.compact
      end
    end

    # 子运行聚合统计结构体
    ChildRunAggregate = Struct.new(
      :key, :label, :model,
      :runs, :completed, :failed, :aborted,
      :prompt_tokens, :completion_tokens, :total_tokens,
      :cost_usd, :cost_cny,
      :average_total_tokens, :average_cost_usd, :average_cost_cny,
      keyword_init: true
    )

    # 基于文件系统的委托存储实现类
    class FileDelegationStore
      # 方法功能：初始化文件委托存储
      # 参数：root_dir - 委托记录存储目录
      def initialize(root_dir)
        @root_dir = root_dir
      end

      # 方法功能：插入或更新子运行记录
      # 参数：record - 子运行记录对象
      # 返回值：void
      def upsert(record)
        FileUtils.mkdir_p(@root_dir)
        path = ::File.join(@root_dir, "#{record.id}.json")
        ::File.write(path, JSON.pretty_generate(record.to_hash))
      end

      # 方法功能：列出子运行记录
      # 参数：parent_thread_id - 可选的父线程 ID 过滤条件
      # 返回值：Array<ChildRunRecord> - 子运行记录列表
      def list(parent_thread_id: nil)
        FileUtils.mkdir_p(@root_dir)
        entries = begin
          Dir.children(@root_dir).select { |e| e.end_with?('.json') }
        rescue StandardError
          []
        end
        records = entries.filter_map do |entry|
          raw = ::File.read(::File.join(@root_dir, entry))
          attrs = JSON.parse(raw, symbolize_names: true)
          ChildRunRecord.from_hash(attrs)
        rescue StandardError
          nil
        end
        records = records.select { |r| r.parent_thread_id == parent_thread_id } if parent_thread_id
        records.sort_by(&:created_at)
      end
    end

    # 委托运行时类，管理子代理执行
    class DelegationRuntime
      # 方法功能：初始化委托运行时
      # 参数：config - 子代理能力配置哈希
      #       store - FileDelegationStore 存储实例
      #       events - 可选的运行时事件记录器
      #       now_iso - 可选的当前时间函数
      #       id_generator - 可选的 ID 生成函数
      #       executor - 可选的子运行执行器
      #       record_external_usage - 可选的外部使用量记录函数
      def initialize(config:, store:, events: nil, now_iso: nil, id_generator: nil, executor: nil,
                     record_external_usage: nil)
        @config = config
        @store = store
        @events = events
        @now_iso = now_iso || -> { Time.now.strftime('%FT%TZ') }
        @id_generator = id_generator || -> { "child_#{Time.now.to_i.to_s(36)}_#{SecureRandom.hex(3)[0, 6]}" }
        @executor = executor || default_executor
        @record_external_usage = record_external_usage
        @active = 0
        @child_seq = 0
        @mutex = Mutex.new
      end

      # 方法功能：执行子代理运行
      # 参数：input - 子运行参数哈希
      # 返回值：ChildRunRecord - 子运行记录
      # 异常：RuntimeError - 如果委托被禁用或预算耗尽
      def run_child(input)
        raise 'delegation is disabled by config' unless @config[:enabled]

        @mutex.synchronize do
          raise 'delegation parallel budget exhausted' if @active >= @config[:max_parallel]
        end

        existing = @store.list(parent_thread_id: input[:parent_thread_id])
        raise 'delegation child-run budget exhausted' if existing.length >= @config[:max_child_runs]

        now = @now_iso.call
        id = @id_generator.call
        record = ChildRunRecord.new(
          id: id,
          parent_thread_id: input[:parent_thread_id],
          parent_turn_id: input[:parent_turn_id],
          label: input[:label],
          prompt: input[:prompt],
          workspace: input[:workspace],
          model: input[:model],
          status: 'running',
          usage: ChildRunUsage.default,
          created_at: now,
          updated_at: now
        )
        @store.upsert(record)
        record_child_event(record)

        @mutex.synchronize { @active += 1 }
        begin
          result = @executor.call(
            child_id: id,
            parent_thread_id: input[:parent_thread_id],
            parent_turn_id: input[:parent_turn_id],
            label: input[:label],
            prompt: input[:prompt],
            workspace: input[:workspace],
            model: input[:model],
            signal: input[:signal]
          )
          record = ChildRunRecord.new(
            **record.to_h,
            status: 'completed',
            summary: result[:summary],
            usage: result[:usage] || record.usage,
            updated_at: @now_iso.call
          )
          @store.upsert(record)
          record_child_event(record)
          record_external_usage_for(record)
          record
        rescue StandardError => e
          status = input[:signal]&.alive? == false ? 'aborted' : 'failed'
          record = ChildRunRecord.new(
            **record.to_h,
            status: status,
            error: error_message(e),
            updated_at: @now_iso.call
          )
          @store.upsert(record)
          record_child_event(record)
          record
        ensure
          @mutex.synchronize { @active -= 1 }
        end
      end

      # 方法功能：获取委托运行时的诊断信息
      # 参数：parent_thread_id - 可选的父线程 ID 过滤条件
      # 返回值：Hash - 包含启用状态、活跃计数、子运行列表、聚合统计的诊断数据
      def diagnostics(parent_thread_id: nil)
        child_runs = @store.list(parent_thread_id: parent_thread_id)
        {
          enabled: @config[:enabled],
          active: @active,
          child_runs: child_runs.map(&:to_hash),
          aggregates: DeepForge::Delegation.aggregate_child_runs(child_runs)
        }
      end

      private

      # 方法功能：记录子运行事件
      # 参数：record - 子运行记录对象
      # 返回值：void
      def record_child_event(record)
        return unless @events

        @mutex.synchronize { @child_seq += 1 }
        event_kind = case record.status
                     when 'completed' then 'turn_completed'
                     when 'failed' then 'turn_failed'
                     when 'aborted' then 'turn_aborted'
                     else 'turn_started'
                     end

        @events.record(
          kind: event_kind,
          thread_id: record.parent_thread_id,
          turn_id: record.parent_turn_id,
          status: record.status,
          text: record.summary || record.error,
          child: {
            parent_thread_id: record.parent_thread_id,
            parent_turn_id: record.parent_turn_id,
            child_id: record.id,
            child_label: record.label,
            child_status: record.status,
            child_seq: @child_seq
          }
        )
      end

      # 方法功能：记录外部使用量
      # 参数：record - 子运行记录对象
      # 返回值：void
      def record_external_usage_for(record)
        return unless record.status == 'completed'
        return unless @record_external_usage

        usage = to_usage_snapshot(record.usage)
        return if usage[:total_tokens] <= 0 && usage[:cost_usd].nil? && usage[:cost_cny].nil?

        @record_external_usage.call(record.parent_thread_id, usage)
      end

      # 方法功能：将子运行使用量转换为使用量快照
      # 参数：usage - 子运行使用量对象
      # 返回值：Hash - 使用量快照哈希
      def to_usage_snapshot(usage)
        {
          prompt_tokens: usage.prompt_tokens,
          completion_tokens: usage.completion_tokens,
          total_tokens: usage.total_tokens,
          cached_tokens: usage.cached_tokens,
          cache_hit_tokens: usage.cache_hit_tokens,
          cache_miss_tokens: usage.cache_miss_tokens,
          cache_hit_rate: usage.cache_hit_rate,
          turns: usage.turns || 0,
          cost_usd: usage.cost_usd,
          cost_cny: usage.cost_cny,
          cache_savings_usd: usage.cache_savings_usd,
          cache_savings_cny: usage.cache_savings_cny,
          token_economy_savings_tokens: usage.token_economy_savings_tokens,
          token_economy_savings_usd: usage.token_economy_savings_usd,
          token_economy_savings_cny: usage.token_economy_savings_cny
        }
      end

      # 方法功能：获取默认执行器（返回提示词作为摘要）
      # 返回值：Proc - 默认执行器函数
      def default_executor
        ->(input) { { summary: "Child result: #{input[:prompt]}" } }
      end

      # 方法功能：安全地获取错误消息
      # 参数：error - 异常对象
      # 返回值：String - 错误消息文本
      def error_message(error)
        error.is_a?(StandardError) ? error.message : error.to_s
      end
    end

    # 方法功能：按标签和模型聚合子运行记录
    # 参数：records - 子运行记录列表
    # 返回值：Array<ChildRunAggregate> - 聚合统计列表
    def self.aggregate_child_runs(records)
      buckets = {}
      records.each do |record|
        label = record.label&.strip
        model = record.model&.strip
        key = "#{label || 'unlabeled'}:#{model || 'default'}"

        bucket = buckets[key] ||= ChildRunAggregate.new(
          key: key,
          label: label,
          model: model,
          runs: 0, completed: 0, failed: 0, aborted: 0,
          prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
          cost_usd: nil, cost_cny: nil,
          average_total_tokens: 0,
          average_cost_usd: nil, average_cost_cny: nil
        )

        bucket.runs += 1
        case record.status
        when 'completed' then bucket.completed += 1
        when 'failed' then bucket.failed += 1
        when 'aborted' then bucket.aborted += 1
        end

        bucket.prompt_tokens += record.usage.prompt_tokens
        bucket.completion_tokens += record.usage.completion_tokens
        bucket.total_tokens += record.usage.total_tokens

        bucket.cost_usd = (bucket.cost_usd || 0) + record.usage.cost_usd if record.usage.cost_usd
        bucket.cost_cny = (bucket.cost_cny || 0) + record.usage.cost_cny if record.usage.cost_cny

        bucket.average_total_tokens = bucket.runs.positive? ? bucket.total_tokens.to_f / bucket.runs : 0
        bucket.average_cost_usd = bucket.cost_usd && bucket.runs.positive? ? bucket.cost_usd / bucket.runs : nil
        bucket.average_cost_cny = bucket.cost_cny && bucket.runs.positive? ? bucket.cost_cny / bucket.runs : nil
      end

      buckets.values.sort_by { |b| [-b.runs, -b.total_tokens, b.key] }
    end
  end
end
