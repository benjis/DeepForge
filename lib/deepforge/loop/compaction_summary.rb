# frozen_string_literal: true

# 文件用途：基于模型的压缩摘要生成器
# 使用方法：通过 DeepForge::Loop::CompactionSummary.summarize_compaction_with_model 调用
# 使用 LLM 生成密集、事实性的摘要，失败时回退到启发式摘要

require 'json'
require 'timeout'

module DeepForge
  module Loop
    # 模块功能：基于模型的压缩摘要生成
    # 使用 LLM 生成会话压缩摘要，支持超时和错误回退
    module CompactionSummary
      # 模型压缩摘要生成的默认超时时间（毫秒）
      DEFAULT_COMPACTION_SUMMARY_TIMEOUT_MS = 15_000

      # 摘要响应的默认最大 token 数
      DEFAULT_COMPACTION_SUMMARY_MAX_TOKENS = 1_200

      # 压缩提示的默认最大输入字节数
      DEFAULT_COMPACTION_SUMMARY_INPUT_MAX_BYTES = 96 * 1024

      # 使用模型生成会话压缩摘要
      #
      # 将会话历史发送给模型，使用结构化提示生成密集的交接摘要。
      # 在超时、取消或错误时返回 nil，允许回退到启发式摘要。
      #
      # @param thread_id [String] 线程标识符
      # @param turn_id [String] 轮次标识符
      # @param model [String] 模型标识符
      # @param model_client [Object] 支持 #stream 方法的模型客户端
      # @param prefix [ImmutablePrefix] 包含系统提示和少量示例的前缀
      # @param context_compaction [Hash, nil] 压缩配置选项
      # @param items [Array<TurnItem>] 要摘要的会话条目
      # @param heuristic_summary [String] 回退的启发式摘要
      # @param signal [Object] 取消信号
      # @param record_usage [Proc, nil] 记录 token 用量的回调
      # @param record_fallback [Proc, nil] 记录回退原因的回调
      # @return [String, nil] 生成的摘要，失败时返回 nil
      def self.summarize_compaction_with_model(
        thread_id:, turn_id:, model:, model_client:, prefix:,
        items:, heuristic_summary:, signal:, context_compaction: nil,
        record_usage: nil, record_fallback: nil
      )
        return nil if signal.aborted?

        timeout_ms = [
          1,
          (context_compaction&.[](:summary_timeout_ms) || DEFAULT_COMPACTION_SUMMARY_TIMEOUT_MS).to_i
        ].max

        fallback_recorded = false

        record_fallback_once = proc do |message|
          next if fallback_recorded || signal.aborted?

          fallback_recorded = true
          record_fallback&.call(message)
        end

        request_item = {
          id: "item_#{turn_id}_compaction_summary_request",
          turn_id: turn_id,
          thread_id: thread_id,
          role: 'user',
          status: 'completed',
          created_at: Time.now.utc.strftime('%FT%TZ'),
          finished_at: Time.now.utc.strftime('%FT%TZ'),
          kind: 'user_message',
          text: build_model_compaction_prompt(
            items: items,
            heuristic_summary: heuristic_summary,
            max_bytes: context_compaction&.[](:summary_input_max_bytes) || DEFAULT_COMPACTION_SUMMARY_INPUT_MAX_BYTES
          )
        }

        text = ''
        max_tokens = [
          1,
          (context_compaction&.[](:summary_max_tokens) || DEFAULT_COMPACTION_SUMMARY_MAX_TOKENS).to_i
        ].max

        # Use a thread with a timeout for cancellation
        thread = Thread.current
        cancelled = false

        timer_thread = Thread.new do
          sleep(timeout_ms / 1000.0)
          cancelled = true
          thread.raise(Timeout::Error) if thread.alive?
        end

        begin
          model_client.stream(
            thread_id: thread_id,
            turn_id: turn_id,
            model: model,
            system_prompt: prefix.system_prompt,
            context_instructions: [
              'Summarize context for a history fold. Preserve durable task state and omit transient chatter.'
            ],
            prefix: prefix.few_shots,
            history: [request_item],
            tools: [],
            stream: true,
            max_tokens: max_tokens,
            temperature: 0,
            reasoning_effort: 'off'
          ) do |chunk|
            if signal.aborted?
              timer_thread.kill
              return nil
            end

            case chunk[:kind]
            when 'assistant_text_delta'
              text += chunk[:text]
            when 'usage'
              record_usage&.call(chunk[:usage])
            when 'error'
              code = chunk[:code] ? " (#{chunk[:code]})" : ''
              record_fallback_once.call(
                "Model compaction summary failed#{code}: #{chunk[:message]}. Using heuristic summary."
              )
              timer_thread.kill
              return nil
            end
          end

          summary = text.strip
          if summary.empty?
            record_fallback_once.call('Model compaction summary returned empty text; using heuristic summary.')
            return nil
          end

          summary
        rescue Timeout::Error
          if cancelled && !signal.aborted?
          end
          reason = "Model compaction summary timed out after #{timeout_ms}ms"
          record_fallback_once.call("#{reason}; using heuristic summary.")
          nil
        rescue StandardError => e
          reason = if cancelled && !signal.aborted?
                     "Model compaction summary timed out after #{timeout_ms}ms"
                   else
                     "Model compaction summary threw: #{e.message}"
                   end
          record_fallback_once.call("#{reason}; using heuristic summary.")
          nil
        ensure
          timer_thread.kill
        end
      end

      # 构建模型压缩的结构化提示
      #
      # @param items [Array<TurnItem>] 要摘要的会话条目
      # @param heuristic_summary [String] 已有的启发式摘要用于交叉检查
      # @param max_bytes [Integer] 最大输入字节数
      # @return [String] 压缩提示文本
      def self.build_model_compaction_prompt(items:, heuristic_summary:, max_bytes:)
        transcript = fit_text_to_bytes(
          items.map { |item| compaction_prompt_line(item) }
               .reject(&:empty?)
               .join("\n"),
          [1024, max_bytes].max
        )

        [
          'You are compacting a long agent conversation so work can continue past the context window.',
          'Write a dense, factual handoff summary using EXACTLY the following section headers, in this order.',
          'Keep every section; write "- (none)" when a section has no content. Use short bullets, not prose.',
          'Do not invent facts, do not add generic advice, and preserve concrete identifiers verbatim',
          '(file paths, function/variable names, commands, URLs, IDs, error messages).',
          '',
          '## Goal',
          "- The user's overall objective and any explicit requirements or constraints.",
          '## Completed',
          '- Work already done and decisions made, with the concrete outcome of each.',
          '## Key findings',
          '- Important facts discovered (root causes, data values, API shapes) needed to continue.',
          '## Files & locations',
          '- Files created/edited/inspected and the relevant paths or line ranges.',
          '## Tool & command results',
          '- Notable tool/command outcomes, especially errors and their resolution status.',
          '## Pending',
          '- Unresolved next steps and anything explicitly requested but not yet done.',
          '## Constraints & pins',
          '- Durable rules, user preferences, and active/pinned skills that must survive.',
          '',
          'Existing heuristic summary to cross-check (may be incomplete):',
          heuristic_summary&.strip&.empty? ? '(none)' : (heuristic_summary || '(none)'),
          '',
          'Conversation history to fold:',
          transcript.empty? ? '(empty)' : transcript
        ].join("\n")
      end

      # 将单个轮次条目格式化为压缩提示行（内部方法）
      #
      # @param item [TurnItem] 会话条目
      # @return [String] 格式化的提示行
      # @api private
      def self.compaction_prompt_line(item)
        case item[:kind]
        when 'user_message'
          "[user] #{clip_for_prompt(item[:text], 2000)}"
        when 'assistant_text'
          "[assistant] #{clip_for_prompt(item[:text], 2000)}"
        when 'assistant_reasoning'
          ''
        when 'tool_call'
          summary = item[:summary] || stringify_for_prompt(item[:arguments])
          "[tool_call:#{item[:tool_name]}] #{clip_for_prompt(summary, 1200)}"
        when 'tool_result'
          error_suffix = item[:is_error] ? ':error' : ''
          output = stringify_for_prompt(item[:output])
          "[tool_result:#{item[:tool_name]}#{error_suffix}] #{clip_for_prompt(output, 2000)}"
        when 'approval'
          "[approval:#{item[:status]}:#{item[:tool_name]}] #{clip_for_prompt(item[:summary], 800)}"
        when 'user_input'
          "[user_input:#{item[:status]}] #{clip_for_prompt(item[:prompt], 800)}"
        when 'compaction'
          item[:replaced_tokens]&.positive? ? "[compaction] #{clip_for_prompt(item[:summary], 2000)}" : ''
        when 'review'
          text = item[:review_text] || stringify_for_prompt(item[:output])
          "[review:#{item[:title]}] #{clip_for_prompt(text, 2000)}"
        when 'error'
          code = item[:code] ? ":#{item[:code]}" : ''
          "[error#{code}] #{clip_for_prompt(item[:message], 1200)}"
        else
          ''
        end
      end
      private_class_method :compaction_prompt_line

      # 将值转换为字符串以包含在提示中（内部方法）
      #
      # @param value [Object] 待转换的值
      # @return [String] 字符串表示
      # @api private
      def self.stringify_for_prompt(value)
        return value if value.is_a?(String)
        return '' if value.nil?

        JSON.generate(value)
      rescue StandardError
        value.to_s
      end
      private_class_method :stringify_for_prompt

      # 将文本截断到最大字符数（内部方法）
      #
      # @param text [String] 待截断的文本
      # @param max_chars [Integer] 最大字符数
      # @return [String] 截断后的文本
      # @api private
      def self.clip_for_prompt(text, max_chars)
        compact = text.gsub(/\s+/, ' ').strip
        return compact if compact.length <= max_chars

        "#{compact[0...([0, max_chars - 3].max)].strip}..."
      end
      private_class_method :clip_for_prompt

      # 将文本适配到字节限制，必要时截断（内部方法）
      #
      # @param text [String] 待适配的文本
      # @param max_bytes [Integer] 最大字节数
      # @return [String] 适配后的文本
      # @api private
      def self.fit_text_to_bytes(text, max_bytes)
        return text if text.bytesize <= max_bytes

        out = +''
        used = 0

        text.each_char do |char|
          bytes = char.bytesize
          break if used + bytes > max_bytes

          out << char
          used += bytes
        end

        "#{out.rstrip}\n...[truncated for model compaction summary]"
      end
      private_class_method :fit_text_to_bytes
    end
  end
end
