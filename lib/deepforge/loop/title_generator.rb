# frozen_string_literal: true

# 文件用途：线程标题生成器，使用 LLM 生成对话的简洁标题
# 使用方法：通过 DeepForge::Loop::TitleGenerator.generate_thread_title 调用

require 'json'
require 'timeout'
require_relative 'reasoning_effort'

module DeepForge
  module Loop
    # 模块功能：基于 LLM 的线程标题生成
    # 使用一次内部 LLM 调用为聊天会话生成简洁标题
    module TitleGenerator
      # 标题生成的默认超时时间（毫秒）
      DEFAULT_TITLE_TIMEOUT_MS = 12_000

      # 标题响应的默认最大 token 数
      DEFAULT_TITLE_MAX_TOKENS = 64

      # 生成标题的最大字符数
      MAX_TITLE_CHARS = 50

      # 标题提示的最大输入字符数
      MAX_TITLE_INPUT_CHARS = 4_000

      # 标题生成 LLM 调用的系统提示词
      TITLE_SYSTEM_PROMPT = [
        'You generate a concise title for a chat conversation.',
        'Output rules:',
        '- Output ONLY the title text on a single line. No quotes, no markdown, no prefix like "Title:".',
        "- Maximum #{MAX_TITLE_CHARS} characters.",
        '- Summarize the user\'s intent, not the assistant\'s actions.',
        '- Never include tool names, file paths, code, or punctuation-only output.',
        '- Write in the same language as the user\'s message.'
      ].join("\n")

      # 解析一次性内部角色调用的模型和 provider_id
      #
      # 使用优先级：角色覆盖 -> 全局 smallModel -> 主对话模型
      #
      # @param role_model [String, nil] 角色特定的模型覆盖
      # @param role_provider_id [String, nil] 角色特定的提供者 ID
      # @param roles [Hash, nil] 角色配置（smallModel, smallModelProviderId）
      # @param main_model [String, nil] 主对话模型
      # @param main_provider_id [String, nil] 主对话提供者 ID
      # @return [Hash, nil] { model: String, provider_id: String } 或 nil（无法解析时）
      def self.resolve_role_model(
        role_model: nil, role_provider_id: nil,
        roles: nil, main_model: nil, main_provider_id: nil
      )
        role = trim(role_model)
        return { model: role, provider_id: trim(role_provider_id) }.compact if role

        small = roles&.[](:small_model) || roles&.[]('smallModel')
        if small
          small_provider = roles&.[](:small_model_provider_id) || roles&.[]('smallModelProviderId')
          return { model: small, provider_id: trim(small_provider) }.compact
        end

        main = trim(main_model)
        return { model: main, provider_id: trim(main_provider_id) }.compact if main

        nil
      end

      # 从对话生成线程标题
      #
      # 将第一条用户消息（和可选的助手回复）发送给模型，
      # 使用结构化提示生成单行标题。在超时、取消或错误时返回 nil。
      #
      # @param thread_id [String] 线程标识符
      # @param turn_id [String] 轮次标识符
      # @param model_client [Object] 支持 #stream 方法的模型客户端
      # @param model [String] 标题角色的模型标识符
      # @param provider_id [String, nil] 可选的提供者路由 ID
      # @param system_prompt [String, nil] 可选的系统提示覆盖
      # @param user_text [String] 第一条用户消息文本（意图）
      # @param assistant_text [String, nil] 第一条助手回复文本（可选上下文）
      # @param reasoning_effort [String, nil] 调用的推理深度
      # @param timeout_ms [Integer, nil] 超时毫秒数
      # @param abort_signal [Object, nil] 取消信号
      # @return [String, nil] 生成的标题，失败时返回 nil
      def self.generate_thread_title(
        thread_id:, turn_id:, model_client:, model:, user_text:, provider_id: nil,
        system_prompt: nil, assistant_text: nil,
        reasoning_effort: nil, timeout_ms: nil, abort_signal: nil
      )
        user_text_val = trim(user_text)
        return nil if user_text_val.empty?
        return nil if abort_signal&.aborted?

        timeout_ms_val = [1, (timeout_ms || DEFAULT_TITLE_TIMEOUT_MS).to_i].max

        controller = Concurrent::Promises.reschedule_event(timeout_ms_val / 1000.0) { nil }

        begin
          prompt_text = build_title_prompt(user_text_val, assistant_text)
          request_item = {
            id: "item_#{turn_id}_title_request",
            turn_id: turn_id,
            thread_id: thread_id,
            role: 'user',
            status: 'completed',
            created_at: Time.now.utc.strftime('%FT%TZ'),
            finished_at: Time.now.utc.strftime('%FT%TZ'),
            kind: 'user_message',
            text: prompt_text
          }

          request = {
            thread_id: thread_id,
            turn_id: "#{turn_id}_title",
            model: model,
            provider_id: provider_id,
            system_prompt: system_prompt,
            context_instructions: [TITLE_SYSTEM_PROMPT],
            prefix: [],
            history: [request_item],
            tools: [],
            stream: true,
            max_tokens: DEFAULT_TITLE_MAX_TOKENS,
            temperature: 0,
            reasoning_effort: normalize_role_reasoning_effort(reasoning_effort),
            abort_signal: abort_signal
          }

          text = ''
          model_client.stream(request).each do |chunk|
            return nil if abort_signal&.aborted?

            case chunk[:kind]
            when 'assistant_text_delta'
              text += chunk[:text]
            when 'error'
              return nil
            end
          end

          sanitize_title(text)
        rescue StandardError
          nil
        ensure
          controller&.cancel
        end
      end

      # 清理原始标题字符串
      #
      # 去除引号、markdown、前导 "Title:" 并限制字符数
      #
      # @param raw [String] 来自 LLM 的原始标题
      # @return [String, nil] 清理后的标题或 nil（为空时）
      def self.sanitize_title(raw)
        title = raw
                .gsub("\r", '')
                .split("\n")
                .map(&:strip)
                .find { |line| !line.empty? } || ''

        title = title.sub(/^title\s*[:：]\s*/i, '')
        title = title.gsub(/^["'「」]+|["'「」]+$/, '')
        title = title.sub(/^#+\s*/, '').gsub(/^\*+|\*+$/, '')
        title = title.gsub(/\s+/, ' ').strip

        return nil if title.empty?

        title = title[0...MAX_TITLE_CHARS].strip if title.length > MAX_TITLE_CHARS
        title.empty? ? nil : title
      end

      class << self
        private

        # 为 LLM 构建标题提示（内部方法）
        #
        # @param user_text [String] 用户的第一条消息
        # @param assistant_text [String, nil] 可选的助手回复
        # @return [String] 格式化的提示
        def build_title_prompt(user_text, assistant_text)
          lines = ['User message:', clip(user_text, MAX_TITLE_INPUT_CHARS)]
          assistant = trim(assistant_text)
          lines.push('', 'Assistant reply (for context only):', clip(assistant, 1_000)) unless assistant.empty?
          lines.push('', "Title (single line, <= #{MAX_TITLE_CHARS} chars):")
          lines.join("\n")
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

        # 修剪字符串或在 nil 时返回空字符串（内部方法）
        #
        # @param value [String, nil] 待修剪的值
        # @return [String] 修剪后的字符串或空字符串
        def trim(value)
          value.is_a?(String) ? value.strip : ''
        end
      end
    end
  end
end
