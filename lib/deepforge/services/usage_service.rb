# frozen_string_literal: true

# 文件用途：用量统计服务
# 使用方法：协调 token 使用量和缓存遥测数据的收集与聚合。支持按线程、日期、模型维度统计，
#           计算缓存命中率和费用估算。提供每日用量查询和模型用量查询功能。

require 'tzinfo'

module DeepForge
  module Services
    # 用量统计和缓存遥测协调服务。
    class UsageService
      # 每日用量查询的最大天数限制
      MAX_DAILY_USAGE_DAYS = 370

      # 初始化用量统计服务
      def initialize
        # 按线程 ID 存储的用量计数器
        @counters = {}
        # 按线程 ID 存储的缓存快照
        @cache = {}
      end

      # 记录一次 API 调用的用量数据
      # 参数：thread_id - 线程 ID，usage - 用量哈希（含 token 数量和费用信息）
      # 返回值：Hash，更新后的用量计数器
      def record(thread_id, usage)
        ingest_cache(thread_id, usage)
        record_counter(thread_id, usage)
      end

      # 记录 token 经济模式带来的节省量
      # 参数：thread_id - 线程 ID，savings - 节省量哈希
      # 返回值：Hash，更新后的用量计数器
      def record_token_economy_savings(thread_id, savings)
        counter = @counters[thread_id] || empty_snapshot
        counter = counter.merge(
          token_economy_savings_tokens: (counter[:token_economy_savings_tokens] || 0) + (savings[:token_economy_savings_tokens] || 0),
          token_economy_savings_usd: (counter[:token_economy_savings_usd] || 0) + (savings[:token_economy_savings_usd] || 0),
          token_economy_savings_cny: (counter[:token_economy_savings_cny] || 0) + (savings[:token_economy_savings_cny] || 0)
        )
        @counters[thread_id] = counter
        counter
      end

      # 用已知的用量数据初始化线程计数器
      # 参数：thread_id - 线程 ID，usage - 初始用量数据
      # 返回值：Hash，初始化后的用量计数器
      def seed_thread(thread_id, usage)
        seeded = @counters[thread_id] || empty_snapshot
        seeded = seeded.merge(usage)
        @counters[thread_id] = seeded
        @cache[thread_id] = {}
        ingest_cache(thread_id, seeded)
        seeded
      end

      # 获取指定线程的用量快照
      # 参数：thread_id - 线程 ID
      # 返回值：Hash，用量快照（含 token 数量、费用等）
      def for_thread(thread_id)
        @counters[thread_id] || empty_snapshot
      end

      # 获取所有线程的总用量
      # 返回值：Hash，汇总后的用量快照
      def total
        result = empty_snapshot
        @counters.each_value do |counter|
          result = add_snapshots(result, counter)
        end
        result
      end

      # 获取指定线程的缓存快照
      # 参数：thread_id - 线程 ID
      # 返回值：Hash，缓存快照（含 cache_hit_tokens 和 cache_miss_tokens）
      def cache_snapshot(thread_id)
        @cache[thread_id] || {}
      end

      # 重置用量数据
      # 参数：thread_id - 线程 ID（可选），为 nil 时重置所有线程
      # 返回值：void
      def reset(thread_id = nil)
        if thread_id
          @counters.delete(thread_id)
          @cache.delete(thread_id)
        else
          @counters.clear
          @cache.clear
        end
      end

      # 解析每日用量查询参数
      # 参数：input - 查询输入哈希，runtime_default_timezone - 默认时区，now - 当前时间
      # 返回值：Hash（含 group_by, from, to, timezone）
      def self.parse_daily_usage_query(input, runtime_default_timezone = default_timezone, now = Time.now)
        group_by = string_param(input, 'group_by') || 'runtime'
        raise UsageValidationError, "unsupported usage grouping: #{group_by}" unless group_by == 'day'

        timezone = string_param(input, 'timezone') || runtime_default_timezone
        assert_valid_timezone(timezone)

        from, to = resolve_usage_window(input, timezone, now, 'daily usage')
        inclusive_day_count(from, to)

        { group_by: 'day', from: from, to: to, timezone: timezone }
      end

      # 解析模型用量查询参数
      # 参数：input - 查询输入哈希，runtime_default_timezone - 默认时区，now - 当前时间
      # 返回值：Hash（含 group_by, from, to, timezone）
      def self.parse_model_usage_query(input, runtime_default_timezone = default_timezone, now = Time.now)
        group_by = string_param(input, 'group_by') || 'runtime'
        raise UsageValidationError, "unsupported usage grouping: #{group_by}" unless group_by == 'model'

        timezone = string_param(input, 'timezone') || runtime_default_timezone
        assert_valid_timezone(timezone)

        from, to = resolve_usage_window(input, timezone, now, 'model usage')
        inclusive_day_count(from, to)

        { group_by: 'model', from: from, to: to, timezone: timezone }
      end

      # 将 ISO 时间戳格式化为指定时区的日期字符串
      # 参数：iso_timestamp - ISO 8601 时间戳，timezone - 时区名称
      # 返回值：String 或 nil，格式化后的日期（YYYY-MM-DD）
      def self.format_date_in_timezone(iso_timestamp, timezone)
        time = Time.parse(iso_timestamp)
        tz = TZInfo::Timezone.get(timezone)
        local_time = tz.to_local(time)
        local_time.strftime('%Y-%m-%d')
      rescue TZInfo::InvalidTimezoneIdentifier, ArgumentError
        nil
      end

      # 按线程维度构建用量响应
      # 参数：records - 用量记录数组
      # 返回值：Hash（含 group_by, buckets, totals）
      def self.build_thread_usage_response(records)
        buckets = {}

        records.each do |record|
          thread_id = record[:thread_id]
          bucket = buckets[thread_id] || empty_thread_bucket(thread_id)
          add_usage_counters(bucket, record[:usage])
          buckets[thread_id] = bucket
        end

        finalized = buckets.values
                           .map { |b| finalize_thread_bucket(b) }
                           .sort_by { |b| -b[:total_tokens] }

        totals = empty_counters
        finalized.each do |bucket|
          add_to_counters(totals, bucket)
        end
        totals[:thread_count] = finalized.length

        { group_by: 'thread', buckets: finalized, totals: totals }
      end

      # 按日期维度构建每日用量响应
      # 参数：records - 用量记录数组，query - 查询参数
      # 返回值：Hash（含 group_by, from, to, timezone, buckets, totals）
      def self.build_daily_usage_response(records, query)
        days = inclusive_day_count(query[:from], query[:to])
        assert_valid_timezone(query[:timezone])

        start_date = Date.parse(query[:from])
        buckets = {}

        days.times do |offset|
          day = (start_date + offset).to_s
          buckets[day] = empty_daily_bucket(day)
        end

        records.each do |record|
          day = format_date_in_timezone(record[:completed_at], query[:timezone])
          next unless day

          bucket = buckets[day]
          next unless bucket

          add_usage_counters(bucket, record[:usage])
          bucket[:thread_ids] ||= Set.new
          bucket[:thread_ids].add(record[:thread_id])
          bucket[:thread_count] = bucket[:thread_ids].size
        end

        finalized = buckets.values.map { |b| finalize_daily_bucket(b) }
        totals = empty_counters
        totals[:days] = days
        totals[:active_days] = 0
        thread_ids = Set.new
        finalized.each do |b|
          add_to_counters(totals, b)
          if (b[:turns] || 0).positive? || (b[:total_tokens] || 0).positive? ||
             (b[:cost_usd] || 0).positive? || (b[:cost_cny] || 0).positive? ||
             (b[:token_economy_savings_tokens] || 0).positive?
            totals[:active_days] += 1
          end
          bucket = buckets[b[:date]]
          bucket[:thread_ids]&.each { |tid| thread_ids.add(tid) } if bucket
        end
        totals[:thread_count] = thread_ids.size

        { group_by: 'day', from: query[:from], to: query[:to], timezone: query[:timezone], buckets: finalized,
          totals: totals }
      end

      # 按模型维度构建用量响应
      # 参数：records - 用量记录数组，query - 查询参数
      # 返回值：Hash（含 group_by, from, to, timezone, buckets, days, totals）
      def self.build_model_usage_response(records, query)
        days = inclusive_day_count(query[:from], query[:to])
        assert_valid_timezone(query[:timezone])

        start_date = Date.parse(query[:from])
        day_buckets = {}
        model_buckets = {}

        days.times do |offset|
          day = (start_date + offset).to_s
          day_buckets[day] = empty_daily_bucket(day)
        end

        records.each do |record|
          day = format_date_in_timezone(record[:completed_at], query[:timezone])
          next unless day

          day_bucket = day_buckets[day]
          next unless day_bucket

          model = record[:model]&.strip || 'unknown'
          model_bucket = model_buckets[model] || empty_model_bucket(model)

          add_usage_counters(day_bucket, record[:usage])
          add_usage_counters(model_bucket, record[:usage])

          day_bucket[:thread_ids] ||= Set.new
          day_bucket[:thread_ids].add(record[:thread_id])
          day_bucket[:thread_count] = day_bucket[:thread_ids].size

          model_bucket[:thread_ids] ||= Set.new
          model_bucket[:thread_ids].add(record[:thread_id])
          model_bucket[:thread_count] = model_bucket[:thread_ids].size

          model_buckets[model] = model_bucket
        end

        finalized_days = day_buckets.values.map { |b| finalize_daily_bucket(b) }
        finalized_models = model_buckets.values
                                        .map { |b| finalize_model_bucket(b) }
                                        .sort_by { |b| -b[:total_tokens] }

        totals = empty_counters
        totals[:days] = days
        totals[:active_days] = 0
        finalized_days.each do |b|
          add_to_counters(totals, b)
          next unless (b[:turns] || 0).positive? || (b[:total_tokens] || 0).positive? ||
                      (b[:cost_usd] || 0).positive? || (b[:cost_cny] || 0).positive? ||
                      (b[:token_economy_savings_tokens] || 0).positive?

          totals[:active_days] += 1
        end
        thread_ids = model_buckets.values.flat_map { |b| b[:thread_ids].to_a }.uniq
        totals[:thread_count] = thread_ids.size

        {
          group_by: 'model',
          from: query[:from],
          to: query[:to],
          timezone: query[:timezone],
          buckets: finalized_models,
          days: finalized_days,
          totals: totals
        }
      end

      private

      # 记录线程用量计数器（内部方法）
      def record_counter(thread_id, usage)
        counter = @counters[thread_id] || empty_snapshot
        counter = add_snapshots(counter, usage)
        @counters[thread_id] = counter
        counter
      end

      # 摄入缓存数据（内部方法）
      def ingest_cache(thread_id, usage)
        @cache[thread_id] ||= {}
        @cache[thread_id][:cache_hit_tokens] =
          (@cache[thread_id][:cache_hit_tokens] || 0) + (usage[:cache_hit_tokens] || 0)
        @cache[thread_id][:cache_miss_tokens] =
          (@cache[thread_id][:cache_miss_tokens] || 0) + (usage[:cache_miss_tokens] || 0)
      end

      # 合并两个用量快照（内部方法）
      def add_snapshots(target, source)
        target.merge(
          prompt_tokens: (target[:prompt_tokens] || 0) + (source[:prompt_tokens] || 0),
          completion_tokens: (target[:completion_tokens] || 0) + (source[:completion_tokens] || 0),
          total_tokens: (target[:total_tokens] || 0) + (source[:total_tokens] || 0),
          cached_tokens: (target[:cached_tokens] || 0) + (source[:cached_tokens] || 0),
          cache_hit_tokens: (target[:cache_hit_tokens] || 0) + (source[:cache_hit_tokens] || 0),
          cache_miss_tokens: (target[:cache_miss_tokens] || 0) + (source[:cache_miss_tokens] || 0),
          turns: (target[:turns] || 0) + (source[:turns] || 0),
          cost_usd: (target[:cost_usd] || 0) + (source[:cost_usd] || 0),
          cost_cny: (target[:cost_cny] || 0) + (source[:cost_cny] || 0),
          cache_savings_usd: (target[:cache_savings_usd] || 0) + (source[:cache_savings_usd] || 0),
          cache_savings_cny: (target[:cache_savings_cny] || 0) + (source[:cache_savings_cny] || 0),
          token_economy_savings_tokens: (target[:token_economy_savings_tokens] || 0) + (source[:token_economy_savings_tokens] || 0),
          token_economy_savings_usd: (target[:token_economy_savings_usd] || 0) + (source[:token_economy_savings_usd] || 0),
          token_economy_savings_cny: (target[:token_economy_savings_cny] || 0) + (source[:token_economy_savings_cny] || 0)
        )
      end

      # 返回空的用量快照模板（内部方法）
      def empty_snapshot
        {
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          cached_tokens: 0,
          cache_hit_tokens: 0,
          cache_miss_tokens: 0,
          cache_hit_rate: nil,
          turns: 0,
          cost_usd: 0,
          cost_cny: 0,
          cache_savings_usd: 0,
          cache_savings_cny: 0,
          token_economy_savings_tokens: 0,
          token_economy_savings_usd: 0,
          token_economy_savings_cny: 0
        }
      end

      # 用量验证错误类
      class UsageValidationError < StandardError
        attr_reader :code

        def initialize(message)
          super
          @code = 'validation_error'
        end
      end

      # 获取默认时区
      def self.default_timezone
        Time.now.zone || 'UTC'
      end

      # 验证时区是否有效
      def self.assert_valid_timezone(timezone)
        TZInfo::Timezone.get(timezone)
      rescue TZInfo::InvalidTimezoneIdentifier
        raise UsageValidationError, "invalid timezone: #{timezone}"
      end

      # 解析用量查询的时间窗口
      def self.resolve_usage_window(input, timezone, now, label)
        from = string_param(input, 'from')
        to = string_param(input, 'to')

        return [from, to] if from && to

        raise UsageValidationError, "#{label} requires both from and to" if from || to

        window = string_param(input, 'window')&.downcase&.gsub('-', '_')
        raise UsageValidationError, "#{label} requires from and to" unless window

        to_date = format_date_in_timezone(now.strftime('%FT%TZ'), timezone)
        raise UsageValidationError, 'invalid usage window date' unless to_date

        days = case window
               when 'today' then 1
               when 'week' then 7
               when 'month' then 30
               when 'all', 'all_time', 'alltime' then MAX_DAILY_USAGE_DAYS
               else
                 raise UsageValidationError, "unsupported usage window: #{window}"
               end

        from_date = (Date.parse(to_date) - (days - 1)).to_s
        [from_date, to_date]
      end

      # 从输入哈希中提取字符串参数
      def self.string_param(input, key)
        value = input[key]
        return nil unless value

        if value.is_a?(Array)
          first = value.first
          first.is_a?(String) && !first.strip.empty? ? first.strip : nil
        elsif value.is_a?(String)
          value.strip.empty? ? nil : value.strip
        end
      end

      # 计算两个日期之间的天数（含首尾）
      def self.inclusive_day_count(from, to)
        start_date = Date.parse(from)
        end_date = Date.parse(to)
        days = (end_date - start_date).to_i + 1

        raise UsageValidationError, 'from must be on or before to' if days <= 0
        if days > MAX_DAILY_USAGE_DAYS
          raise UsageValidationError,
                "daily usage range must be #{MAX_DAILY_USAGE_DAYS} days or less"
        end

        days
      end

      # 返回空的用量计数器模板
      def self.empty_counters
        {
          input_tokens: 0,
          output_tokens: 0,
          reasoning_tokens: 0,
          cached_tokens: 0,
          cache_miss_tokens: 0,
          total_tokens: 0,
          cost_usd: 0,
          cost_cny: 0,
          cache_savings_usd: 0,
          cache_savings_cny: 0,
          token_economy_savings_tokens: 0,
          token_economy_savings_usd: 0,
          token_economy_savings_cny: 0,
          turns: 0,
          thread_count: 0,
          cache_hit_rate: nil
        }
      end

      # 将用量数据累加到桶中
      def self.add_usage_counters(bucket, usage)
        cached = usage[:cache_hit_tokens] || 0
        miss = usage[:cache_miss_tokens] || 0

        bucket[:input_tokens] = (bucket[:input_tokens] || 0) + (usage[:prompt_tokens] || 0)
        bucket[:output_tokens] = (bucket[:output_tokens] || 0) + (usage[:completion_tokens] || 0)
        bucket[:reasoning_tokens] = (bucket[:reasoning_tokens] || 0)
        bucket[:cached_tokens] = (bucket[:cached_tokens] || 0) + cached
        bucket[:cache_miss_tokens] = (bucket[:cache_miss_tokens] || 0) + miss
        bucket[:total_tokens] = (bucket[:total_tokens] || 0) + (usage[:total_tokens] || 0)
        bucket[:cost_usd] = (bucket[:cost_usd] || 0) + (usage[:cost_usd] || 0)
        bucket[:cost_cny] = (bucket[:cost_cny] || 0) + (usage[:cost_cny] || 0)
        bucket[:cache_savings_usd] = (bucket[:cache_savings_usd] || 0) + (usage[:cache_savings_usd] || 0)
        bucket[:cache_savings_cny] = (bucket[:cache_savings_cny] || 0) + (usage[:cache_savings_cny] || 0)
        bucket[:token_economy_savings_tokens] =
          (bucket[:token_economy_savings_tokens] || 0) + (usage[:token_economy_savings_tokens] || 0)
        bucket[:token_economy_savings_usd] =
          (bucket[:token_economy_savings_usd] || 0) + (usage[:token_economy_savings_usd] || 0)
        bucket[:token_economy_savings_cny] =
          (bucket[:token_economy_savings_cny] || 0) + (usage[:token_economy_savings_cny] || 0)
        bucket[:turns] = (bucket[:turns] || 0) + (usage[:turns] || 0)
      end

      # 将源计数器的值累加到目标计数器
      def self.add_to_counters(target, source)
        %i[input_tokens output_tokens reasoning_tokens cached_tokens cache_miss_tokens total_tokens
           cost_usd cost_cny cache_savings_usd cache_savings_cny
           token_economy_savings_tokens token_economy_savings_usd token_economy_savings_cny turns].each do |key|
          target[key] = (target[key] || 0) + (source[key] || 0)
        end
      end

      # 创建空的每日用量桶
      def self.empty_daily_bucket(date)
        empty_counters.merge(date: date, thread_count: 0)
      end

      # 创建空的线程用量桶
      def self.empty_thread_bucket(thread_id)
        empty_counters.merge(thread_id: thread_id)
      end

      # 创建空的模型用量桶
      def self.empty_model_bucket(model)
        empty_counters.merge(model: model, thread_count: 0)
      end

      # 完成每日用量桶的计算（计算缓存命中率）
      def self.finalize_daily_bucket(bucket)
        finalize_cache_rate(bucket)
      end

      # 完成线程用量桶的计算（计算缓存命中率）
      def self.finalize_thread_bucket(bucket)
        finalize_cache_rate(bucket)
      end

      # 完成模型用量桶的计算（计算缓存命中率）
      def self.finalize_model_bucket(bucket)
        finalize_cache_rate(bucket)
      end

      # 计算并设置缓存命中率
      def self.finalize_cache_rate(counters)
        cache_total = (counters[:cached_tokens] || 0) + (counters[:cache_miss_tokens] || 0)
        counters[:cache_hit_rate] = cache_total.positive? ? (counters[:cached_tokens] || 0).to_f / cache_total : nil
        counters
      end
    end
  end
end
