# frozen_string_literal: true

# 文件用途：会话摘要生成器，使用 LLM 生成会话的简短摘要
# 使用方法：通过 DeepForge::Loop::SessionSummary.generate_session_summary 调用

require 'json'
require 'timeout'
require_relative 'reasoning_effort'

module DeepForge
  module Loop
    # 模块功能：基于 LLM 的会话摘要生成
    # 生成整个聊天会话的简短、中性摘要
    module SessionSummary
      # 会话摘要生成的默认超时时间（毫秒）
      DEFAULT_SESSION_SUMMARY_TIMEOUT_MS = 20_000

      # 摘要响应的默认最大 token 数
      DEFAULT_SESSION_SUMMARY_MAX_TOKENS = 400

      # 摘要提示的默认最大输入字节数
      DEFAULT_SESSION_SUMMARY_INPUT_MAX_BYTES = 96 * 1024

      # 会话摘要 LLM 调用的系统提示词
      SESSION_SUMMARY_SYSTEM_PROMPT = [
        'You write a short, neutral summary of an entire chat conversation.',
        'Output rules:',
        '- Output ONE paragraph (roughly 2-4 sentences). No headings, no bullet lists, no markdown.',
        '- Describe what the user wanted and what was accomplished or concluded.',
        '- Do not invent facts. Do not include tool names or raw code.',
        '- Write in the same language as the conversation.'
      ].join("\n")

      # 从会话记录生成会话摘要
      #
      # 将会话历史发送给模型，使用结构化提示生成一段式摘要。
      # 在超时、取消或错误时返回 nil。
      #
      # @param thread_id [String] 线程标识符
      # @param model_client [Object] 支持 #stream 方法的模型客户端
      # @param model [String] 摘要角色的模型标识符
      # @param provider_id [String, nil] 可选的提供者路由 ID
      # @param system_prompt [String, nil] 可选的系统提示覆盖
      # @param items [Array<TurnItem>] 要摘要的会话条目
      # @param reasoning_effort [String, nil] 调用的推理深度
      # @param timeout_ms [Integer, nil] 超时毫秒数
      # @param max_tokens [Integer, nil] 响应的最大 token 数
      # @param input_max_bytes [Integer, nil] 最大输入字节数
      # @param abort_signal [Object, nil] 取消信号
      # @return [String, nil] 生成的摘要，失败时返回 nil
      def self.generate_session_summary(
        thread_id:, model_client:, model:, items:, provider_id: nil,
        system_prompt: nil, reasoning_effort: nil,
        timeout_ms: nil, max_tokens: nil, input_max_bytes: nil,
        abort_signal: nil
      )
        return nil if abort_signal&.aborted?

        input_max_bytes_val = input_max_bytes || DEFAULT_SESSION_SUMMARY_INPUT_MAX_BYTES
        transcript = build_session_transcript(items, input_max_bytes_val)
        return nil if transcript.strip.empty?

        timeout_ms_val = [1, (timeout_ms || DEFAULT_SESSION_SUMMARY_TIMEOUT_MS).to_i].max
        max_tokens_val = [1, (max_tokens || DEFAULT_SESSION_SUMMARY_MAX_TOKENS).to_i].max

        controller = Concurrent::Promises.reschedule_event(timeout_ms_val / 1000.0) { nil }
        # NOTE: In Ruby, we don't have AbortController, so we'll use a simple timeout thread.

        text = ''
        begin
          turn_id = "#{thread_id}_session_summary"
          request_item = {
            id: "item_#{turn_id}_request",
            turn_id: turn_id,
            thread_id: thread_id,
            role: 'user',
            status: 'completed',
            created_at: Time.now.utc.strftime('%FT%TZ'),
            finished_at: Time.now.utc.strftime('%FT%TZ'),
            kind: 'user_message',
            text: "Conversation transcript:\n#{transcript}\n\nWrite the one-paragraph summary now."
          }

          request = {
            thread_id: thread_id,
            turn_id: turn_id,
            model: model,
            provider_id: provider_id,
            system_prompt: system_prompt,
            context_instructions: [SESSION_SUMMARY_SYSTEM_PROMPT],
            prefix: [],
            history: [request_item],
            tools: [],
            stream: true,
            max_tokens: max_tokens_val,
            temperature: 0,
            reasoning_effort: normalize_role_reasoning_effort(reasoning_effort),
            abort_signal: abort_signal
          }

          model_client.stream(request).each do |chunk|
            return nil if abort_signal&.aborted?

            case chunk[:kind]
            when 'assistant_text_delta'
              text += chunk[:text]
            when 'error'
              return nil
            end
          end

          summary = text.gsub(/\s+/, ' ').strip
          summary.empty? ? nil : summary
        rescue StandardError
          nil
        ensure
          controller&.cancel
        end
      end

      # 从会话条目构建会话记录
      #
      # @param items [Array<TurnItem>] 会话条目
      # @param max_bytes [Integer] 记录的最大字节数
      # @return [String] 格式化的记录
      def self.build_session_transcript(items, max_bytes)
        text = items.map { |item| transcript_line(item) }
                    .reject(&:empty?)
                    .join("\n")
        fit_text_to_bytes(text, [1_024, max_bytes].max)
      end

      class << self
        private

        # 为单个轮次条目生成记录行（内部方法）
        #
        # @param item [Hash] 轮次条目
        # @return [String] 格式化的记录行
        def transcript_line(item)
          case item[:kind]
          when 'user_message'
            "[user] #{clip(item[:text], 2_000)}"
          when 'assistant_text'
            "[assistant] #{clip(item[:text], 2_000)}"
          when 'tool_call'
            "[tool_call:#{item[:tool_name]}] #{clip(item[:summary] || stringify(item[:arguments]), 600)}"
          when 'tool_result'
            error_suffix = item[:is_error] ? ':error' : ''
            "[tool_result:#{item[:tool_name]}#{error_suffix}] #{clip(stringify(item[:output]), 800)}"
          when 'compaction'
            item[:replaced_tokens]&.positive? ? "[earlier summary] #{clip(item[:summary], 2_000)}" : ''
          when 'review'
            "[review:#{item[:title]}] #{clip(item[:review_text] || stringify(item[:output]), 1_200)}"
          when 'error'
            code_suffix = item[:code] ? ":#{item[:code]}" : ''
            "[error#{code_suffix}] #{clip(item[:message], 600)}"
          else
            ''
          end
        end

        # 将值转换为字符串表示（内部方法）
        #
        # @param value [Object] 待转换的值
        # @return [String] 字符串表示
        def stringify(value)
          return value if value.is_a?(String)
          return '' if value.nil?

          JSON.generate(value)
        rescue StandardError
          value.to_s
        end

        # 将文本截断到最大字符数（内部方法）
        #
        # @param text [String] 待截断的文本
        # @param max_chars [Integer] 最大字符数
        # @return [String] 截断后的文本
        def clip(text, max_chars)
          compact = text.gsub(/\s+/, ' ').strip
          return compact if compact.length <= max_chars

          "#{compact[0...(max_chars - 3)].strip}..."
        end

        # 将文本适配到最大字节数（内部方法）
        #
        # @param text [String] 待适配的文本
        # @param max_bytes [Integer] 最大字节数
        # @return [String] 适配后的文本
        def fit_text_to_bytes(text, max_bytes)
          return text if text.bytesize <= max_bytes

          used = 0
          out = ''
          text.each_char do |char|
            bytes = char.bytesize
            break if used + bytes > max_bytes

            out += char
            used += bytes
          end
          "#{out.rstrip}\n...[truncated]"
        end
      end
    end
  end
end
