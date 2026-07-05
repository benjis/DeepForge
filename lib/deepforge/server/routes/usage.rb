# frozen_string_literal: true

# 文件用途：使用量路由模块，统计和报告 API 使用量（Token 消耗等）
# 使用方法：通过 GET /v1/usage 端点获取使用量统计

require 'json'
require_relative '../response'

module DeepForge
  module Server
    module Routes
      # 使用量端点模块，提供 Token 使用量统计功能
      module Usage
        # 构建包含总量和每线程使用量的响应
        # @param runtime [ServerRuntime] 运行时实例
        # @return [Hash] 使用量响应
        def self.build_usage_response(runtime)
          threads = runtime[:thread_service].list
          {
            total: runtime[:usage_service].total,
            perThread: threads.map do |thread|
              {
                threadId: thread[:id],
                usage: runtime[:usage_service].for_thread(thread[:id])
              }
            end
          }
        end

        # 根据 group_by 参数构建使用量 JSON 响应
        # @param request [Hash] 请求对象
        # @param runtime [ServerRuntime] 运行时实例
        # @return [JsonResponse] 使用量响应
        def self.usage_json_response(request, runtime)
          url = URI(request[:url])
          query_params = URI.decode_www_form(url.query || '').to_h
          group_by = query_params['group_by'] || 'runtime'

          case group_by
          when 'thread'
            DeepForge::Server.json_response(build_thread_usage_response(usage_records(runtime)))
          when 'day'
            DeepForge::Server.json_response(build_daily_usage_response(usage_records(runtime), query_params))
          when 'model'
            DeepForge::Server.json_response(build_model_usage_response(usage_records(runtime), query_params))
          when 'runtime'
            DeepForge::Server.json_response(build_usage_response(runtime))
          else
            DeepForge::Server.json_response(
              { code: 'validation_error', message: "unsupported usage grouping: #{group_by}" }, 400
            )
          end
        end

        # 构建线程级别的使用量响应
        # @param records [Array] 使用量记录
        # @return [Hash] 线程使用量响应
        def self.build_thread_usage_response(records)
          # Group records by thread and sum usage
          thread_usage = {}
          records.each do |record|
            thread_id = record[:thread_id]
            thread_usage[thread_id] ||= { promptTokens: 0, completionTokens: 0, totalTokens: 0, turns: 0 }
            thread_usage[thread_id][:promptTokens] += record[:usage][:promptTokens]
            thread_usage[thread_id][:completionTokens] += record[:usage][:completionTokens]
            thread_usage[thread_id][:totalTokens] += record[:usage][:totalTokens]
            thread_usage[thread_id][:turns] += record[:usage][:turns]
          end
          thread_usage
        end

        # 构建每日使用量响应
        # @param records [Array] 使用量记录
        # @param query [Hash] 查询参数
        # @return [Hash] 每日使用量响应
        def self.build_daily_usage_response(records, _query)
          # Group records by day
          daily_usage = {}
          records.each do |record|
            day = record[:completedAt]&.split('T')&.first || 'unknown'
            daily_usage[day] ||= { promptTokens: 0, completionTokens: 0, totalTokens: 0, turns: 0 }
            daily_usage[day][:promptTokens] += record[:usage][:promptTokens]
            daily_usage[day][:completionTokens] += record[:usage][:completionTokens]
            daily_usage[day][:totalTokens] += record[:usage][:totalTokens]
            daily_usage[day][:turns] += record[:usage][:turns]
          end
          daily_usage
        end

        # 构建模型级别的使用量响应
        # @param records [Array] 使用量记录
        # @param query [Hash] 查询参数
        # @return [Hash] 模型使用量响应
        def self.build_model_usage_response(records, _query)
          # Group records by model
          model_usage = {}
          records.each do |record|
            model = record[:model] || 'unknown'
            model_usage[model] ||= { promptTokens: 0, completionTokens: 0, totalTokens: 0, turns: 0 }
            model_usage[model][:promptTokens] += record[:usage][:promptTokens]
            model_usage[model][:completionTokens] += record[:usage][:completionTokens]
            model_usage[model][:totalTokens] += record[:usage][:totalTokens]
            model_usage[model][:turns] += record[:usage][:turns]
          end
          model_usage
        end

        # 从运行时构建使用量记录
        # @param runtime [ServerRuntime] 运行时实例
        # @return [Array] 使用量记录列表
        def self.usage_records(runtime)
          records = []
          thread_summaries = runtime[:thread_service].list

          thread_summaries.each do |thread_summary|
            thread = runtime[:thread_service].get(thread_summary[:id]) || thread_summary.merge(turns: [])
            latest_persisted = empty_usage_snapshot
            events = runtime[:session_store].load_events_since(thread[:id], 0)
            usage_events = events
                           .select { |e| e[:kind] == 'usage' }
                           .sort_by { |e| e[:seq] }

            usage_events.each do |event|
              delta = diff_usage(event[:usage], latest_persisted)
              latest_persisted = event[:usage]
              next unless has_usage?(delta)

              records << {
                threadId: thread[:id],
                model: usage_record_model(thread, event),
                completedAt: event[:timestamp],
                usage: delta
              }
            end

            live_remainder = diff_usage(runtime[:usage_service].for_thread(thread[:id]), latest_persisted)
            next unless has_usage?(live_remainder)

            records << {
              threadId: thread[:id],
              model: usage_record_model(thread, { turnId: thread[:turns]&.last&.dig(:id) }),
              completedAt: thread[:updatedAt] || runtime[:now_iso].call,
              usage: live_remainder
            }
          end

          records
        end

        # 确定使用量记录对应的模型
        # @param thread [Hash] 线程记录
        # @param event [Hash, nil] 事件记录
        # @return [String] 模型名称
        def self.usage_record_model(thread, event = nil)
          event_model = event&.dig(:model)&.strip
          return event_model if event_model && !event_model.empty?

          trimmed_turn_id = event&.dig(:turnId)&.strip || ''
          if trimmed_turn_id
            turn_model = thread[:turns]&.find { |t| t[:id] == trimmed_turn_id }&.dig(:model)&.strip
            return turn_model if turn_model && !turn_model.empty?
          end

          latest_turn_model = thread[:turns]&.reverse&.find { |t| t[:model]&.strip }&.dig(:model)&.strip
          return latest_turn_model if latest_turn_model && !latest_turn_model.empty?

          thread_model = thread[:model]&.strip
          return thread_model if thread_model && !thread_model.empty?

          'unknown'
        end

        # 计算当前和之前快照之间的使用量差异
        # @param current [Hash] 当前使用量快照
        # @param previous [Hash] 之前使用量快照
        # @return [Hash] 使用量差异
        def self.diff_usage(current, previous)
          prompt_tokens = diff_number(current[:promptTokens], previous[:promptTokens])
          completion_tokens = diff_number(current[:completionTokens], previous[:completionTokens])
          reported_total = diff_number(current[:totalTokens], previous[:totalTokens])
          total_tokens = reported_total.positive? ? reported_total : prompt_tokens + completion_tokens

          {
            promptTokens: prompt_tokens,
            completionTokens: completion_tokens,
            totalTokens: total_tokens,
            turns: diff_number(current[:turns], previous[:turns])
          }
        end

        # 计算数值差异
        # @param current [Numeric] 当前值
        # @param previous [Numeric] 之前的值
        # @return [Numeric] 差异值（非负数）
        def self.diff_number(current, previous)
          [0, current.to_i - previous.to_i].max
        end

        # 检查使用量快照是否有非零值
        # @param usage [Hash] 使用量快照
        # @return [Boolean] 如果有非零值返回 true
        def self.has_usage?(usage)
          usage[:promptTokens].positive? ||
            usage[:completionTokens].positive? ||
            usage[:totalTokens].positive? ||
            usage[:turns].positive?
        end

        # 创建空的使用量快照
        # @return [Hash] 空的使用量快照
        def self.empty_usage_snapshot
          {
            promptTokens: 0,
            completionTokens: 0,
            totalTokens: 0,
            turns: 0
          }
        end
      end
    end
  end
end
