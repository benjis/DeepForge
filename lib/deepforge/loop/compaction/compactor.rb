# frozen_string_literal: true

# 文件用途：上下文压缩器，将长历史折叠为单个压缩条目
# 使用方法：通过 ContextCompactor.new(soft_threshold:, hard_threshold:) 创建实例
# 在保持不可变前缀中固定的用户、项目和技能约束的同时压缩历史

require_relative 'estimator'
require_relative 'marker'
require_relative '../model_context_profile'

# 类功能：上下文压缩器
# 将长历史折叠为单个压缩条目，同时保留不可变前缀中的固定约束
module DeepForge
  module Loop
    class ContextCompactor
      # 软阈值（触发压缩的 token 数）和硬阈值（强制压缩的 token 数）
      attr_reader :soft_threshold, :hard_threshold

      # 初始化上下文压缩器
      # @param soft_threshold [Integer, nil] 软阈值，默认使用模型配置
      # @param hard_threshold [Integer, nil] 硬阈值，默认使用模型配置
      def initialize(soft_threshold: nil, hard_threshold: nil)
        @estimator = ContextEstimator.new
        @soft_threshold = soft_threshold || ModelContextProfile::DEFAULT_CONTEXT_THRESHOLDS[:soft_threshold]
        @hard_threshold = hard_threshold || ModelContextProfile::DEFAULT_CONTEXT_THRESHOLDS[:hard_threshold]
      end

      # 估算条目的 token 数量
      # @param items [Array<Hash>] 轮次条目
      # @return [Integer] 估算的 token 数
      def estimate(items)
        @estimator.estimate_items(items)
      end

      # 判断是否需要压缩
      # @param items [Array<Hash>] 轮次条目
      # @param options [Hash] 可选参数
      # @return [Boolean] 是否需要压缩
      def should_compact(items, model: nil, prompt_tokens: nil, frozen_message_count: nil)
        !plan_compaction(items, model: model, prompt_tokens: prompt_tokens,
                                frozen_message_count: frozen_message_count).nil?
      end

      # 规划压缩方案，确定压缩模式和保留的最近条目数
      # @param items [Array<Hash>] 轮次条目
      # @param options [Hash] 可选参数
      # @return [Hash, nil] 压缩计划或 nil
      def plan_compaction(items, model: nil, prompt_tokens: nil, frozen_message_count: nil)
        frozen_count = normalize_frozen_message_count(frozen_message_count, items.length)
        compactable_items = frozen_count.positive? ? items[frozen_count..] : items
        estimated_tokens = estimate(compactable_items)
        tokens = [estimated_tokens, prompt_tokens || 0].max

        return nil if tokens < @soft_threshold

        aggressive_threshold = @soft_threshold + ((@hard_threshold - @soft_threshold) * 0.6).to_i
        mode = if tokens >= @hard_threshold
                 :force
               elsif tokens >= aggressive_threshold
                 :aggressive
               else
                 :normal
               end

        keep_recent = case mode
                      when :force then 1
                      when :aggressive then 2
                      else 4
                      end

        source = prompt_tokens && prompt_tokens >= estimated_tokens ? 'usage prompt_tokens' : 'estimated prompt tokens'
        {
          mode: mode,
          keep_recent: keep_recent,
          reason: "#{source} #{tokens} reached #{mode} compaction threshold"
        }
      end

      # 执行历史压缩，将长历史折叠为压缩条目
      # @param input [Hash] 包含 thread_id, turn_id, history, prefix 等参数
      # @return [Hash] 包含 next（压缩后历史）、summary_item（摘要条目）、replaced_tokens（替换的 token 数）
      def compact(input)
        history = input[:history]
        frozen_count = normalize_frozen_message_count(input[:frozen_message_count], history.length)
        frozen = frozen_count.positive? ? history[0...frozen_count] : []
        trimmed_history = trim_trailing_tool_calls(history[frozen_count..])
        keep_recent = [0, input[:keep_recent] || 4].max

        if trimmed_history.length <= 1 || trimmed_history.length - keep_recent <= 0
          summary_item = make_compaction_item(
            id: "compaction_#{input[:turn_id]}_noop",
            turn_id: input[:turn_id],
            thread_id: input[:thread_id],
            summary: 'no compaction needed',
            replaced_tokens: 0,
            pinned_constraints: input[:prefix][:pinned_constraints]
          )
          return { next: frozen + trimmed_history, summary_item: summary_item, replaced_tokens: 0 }
        end

        head = keep_recent.zero? ? trimmed_history : trimmed_history[0...-keep_recent]
        tail = keep_recent.zero? ? [] : trimmed_history[-keep_recent..]
        replaced_tokens = @estimator.estimate_items(head)
        source_digest = CompactionMarker.compute_short_hash(CompactionMarker.compacted_items_digest_source(head))
        digest_marker = CompactionMarker.create_tool_digest_marker(source_digest)

        summary = input[:summary_override]&.strip || build_compaction_summary(
          history: trimmed_history,
          head: head,
          tail: tail,
          prefix: input[:prefix],
          reason: input[:reason],
          mode: input[:mode],
          budget_tokens: input[:budget_tokens]
        )

        summary = "#{summary}\n\nCompaction digest marker: #{digest_marker}" unless summary.include?(digest_marker)

        summary_item = make_compaction_item(
          id: "compaction_#{input[:turn_id]}_#{Time.now.to_i}",
          turn_id: input[:turn_id],
          thread_id: input[:thread_id],
          summary: summary,
          replaced_tokens: replaced_tokens,
          pinned_constraints: input[:prefix][:pinned_constraints],
          source_digest: source_digest,
          digest_marker: digest_marker,
          source_item_ids: head.map { |item| item[:id] }
        )

        { next: frozen + [summary_item] + tail, summary_item: summary_item, replaced_tokens: replaced_tokens }
      end

      # 修剪历史末尾的连续工具调用（保留未完成的工具调用）
      def self.trim_trailing_tool_calls(history)
        end_idx = history.length
        while end_idx.positive?
          item = history[end_idx - 1]
          break if item[:kind] != 'tool_call'

          end_idx -= 1
        end
        end_idx == history.length ? history : history[0...end_idx]
      end

      private

      # 标准化冻结消息数量（不能超过历史长度）
      def normalize_frozen_message_count(value, history_length)
        return 0 if value.nil?
        return 0 unless value.is_a?(Numeric) && value.finite?

        [0, [history_length, value.floor].min].max
      end

      # 构建压缩摘要文本
      def build_compaction_summary(history:, head:, tail:, prefix:, reason: nil, mode: nil, budget_tokens: nil)
        content_budget = summary_char_budget(budget_tokens)
        lines = []
        lines << "Reason: #{reason}" if reason
        lines << "Mode: #{mode}" if mode
        lines << "Budget: #{budget_tokens} tokens" if budget_tokens
        lines << 'Pinned constraints (preserved across compaction):'

        if prefix[:pinned_constraints].empty?
          lines << '- (none)'
        else
          prefix[:pinned_constraints].each { |c| lines << "- #{c}" }
        end

        skill_pins = extract_skill_pins(history)
        unless skill_pins.empty?
          lines << 'Pinned skills (preserved across compaction):'
          skill_pins.each { |s| lines << "- #{s}" }
          lines << ''
        end

        lines << ''
        lines << "Summarized #{history.length} item(s); #{tail.length} recent item(s) are also kept verbatim for the current request."
        lines << 'Conversation and work summary:'

        summary_lines = fit_lines_to_budget(
          select_summary_lines(history.map { |i| summarize_item(i) }.reject(&:empty?)),
          content_budget
        )

        if summary_lines.empty?
          lines << '- No user-visible content before compaction.'
        else
          lines.concat(summary_lines)
        end

        lines.join("\n")
      end

      # 从历史中提取固定的技能信息
      def extract_skill_pins(history)
        pins = Set.new
        history.each do |item|
          next unless %w[user_message assistant_text compaction].include?(item[:kind])

          text = item[:kind] == 'compaction' ? item[:summary] : item[:text]
          text.to_s.split(/\r?\n/).each do |line|
            trimmed = line.strip
            pins.add(clip_text(trimmed, 600)) if trimmed.match?(/^(Active Skill:|Skill Pin:|Pinned Skill:)/i)
          end
        end
        pins.to_a
      end

      # 将单个条目转换为摘要行
      def summarize_item(item)
        case item[:kind]
        when 'user_message'
          "- User: #{clip_text(item[:text])}"
        when 'assistant_text'
          "- Assistant: #{clip_text(item[:text])}"
        when 'assistant_reasoning'
          ''
        when 'tool_call'
          summary_text = item[:summary] || compact_stringify(item[:arguments])
          "- Tool call #{item[:tool_name]}: #{clip_text(summary_text)}"
        when 'tool_result'
          error_marker = item[:is_error] ? ' error' : ''
          "- Tool result #{item[:tool_name]}#{error_marker}: #{clip_text(compact_stringify(item[:output]))}"
        when 'approval'
          "- Approval #{item[:status]} for #{item[:tool_name]}: #{clip_text(item[:summary])}"
        when 'user_input'
          "- User input #{item[:status]}: #{clip_text(item[:prompt])}"
        when 'compaction'
          if item[:replaced_tokens]&.positive?
            "- Earlier compaction summary: #{clip_text(item[:summary],
                                                       600)}"
          else
            ''
          end
        when 'review'
          "- Review #{item[:title]}: #{clip_text(item[:review_text] || compact_stringify(item[:output]))}"
        when 'error'
          code_part = item[:code] ? " #{item[:code]}" : ''
          "- Error#{code_part}: #{clip_text(item[:message])}"
        else
          ''
        end
      end

      # 选择摘要行，当行数过多时保留头部和尾部
      def select_summary_lines(lines)
        return lines if lines.length <= 20

        start = lines[0...4]
        tail = lines[-14..]
        omitted = lines.length - start.length - tail.length
        start + ["- #{omitted} middle item(s) omitted from this compact summary."] + tail
      end

      # 将行适配到预算限制内
      def fit_lines_to_budget(lines, budget)
        out = []
        used = 0
        lines.each do |line|
          next_cost = line.length + 1
          if used + next_cost <= budget
            out << line
            used += next_cost
            next
          end
          remaining = budget - used
          out << clip_text(line, remaining) if remaining > 80
          break
        end
        out
      end

      # 将值紧凑地序列化为字符串
      def compact_stringify(value)
        return value if value.is_a?(String)
        return '' if value.nil?

        value.to_json
      rescue StandardError
        value.to_s
      end

      # 截断文本到最大长度
      def clip_text(text, max = 360)
        compact = text.to_s.gsub(/\s+/, ' ').strip
        return compact if compact.length <= max

        "#{compact[0, [0, max - 3].max].strip}..."
      end

      # 计算摘要的字符预算
      def summary_char_budget(budget_tokens)
        return 4000 if budget_tokens.nil?

        [1200, [12_000, budget_tokens * 4].min].max
      end

      # 创建压缩条目对象
      def make_compaction_item(id:, turn_id:, thread_id:, summary:, replaced_tokens:, pinned_constraints:,
                               source_digest: nil, digest_marker: nil, source_item_ids: nil)
        {
          id: id,
          kind: 'compaction',
          turn_id: turn_id,
          thread_id: thread_id,
          summary: summary,
          replaced_tokens: replaced_tokens,
          pinned_constraints: pinned_constraints,
          source_digest: source_digest,
          digest_marker: digest_marker,
          source_item_ids: source_item_ids
        }
      end
    end
  end
end
