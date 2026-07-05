# frozen_string_literal: true

# 文件用途：自动模型路由器，用于在 flash 和 pro 模型之间智能选择
# 使用方法：通过 AutoModelRouter.resolve(input) 获取模型路由决策
# 根据用户输入的复杂度自动选择 deepseek-v4-flash（简单任务）或 deepseek-v4-pro（复杂任务）

require 'json'

# 模块功能：自动模型路由器
# 根据输入复杂度自动选择合适的模型和推理努力级别
module DeepForge
  module Loop
    module AutoModelRouter
      module_function

      # 路由器使用的模型
      AUTO_MODEL_ROUTER_MODEL = 'deepseek-v4-flash'
      # flash 模型名称（用于简单任务）
      AUTO_MODEL_FLASH = 'deepseek-v4-flash'
      # pro 模型名称（用于复杂任务）
      AUTO_MODEL_PRO = 'deepseek-v4-pro'
      # 路由器超时时间（毫秒）
      AUTO_MODEL_ROUTER_TIMEOUT_MS = 4_000

      # 路由器系统提示词
      AUTO_MODEL_ROUTER_SYSTEM_PROMPT = [
        'You are the DeepSeek TUI auto-routing classifier. Return only compact JSON:',
        '{"model":"deepseek-v4-flash|deepseek-v4-pro","thinking":"off|high|max"}.',
        'Use deepseek-v4-flash for trivial, conversational, status, or single-step work.',
        'Use deepseek-v4-pro for coding, debugging, release work, multi-step tasks, high-risk decisions, tool-heavy work, ambiguous requests, or anything that benefits from deeper reasoning.',
        'Use thinking off only for trivial no-tool answers, high for ordinary reasoning, and max for agentic, coding, multi-file, release, architecture, debugging, security, tool-heavy, or uncertain work.'
      ].join(' ')

      # 解析自动模型路由
      # @param input [Hash] 路由输入参数
      # @return [Hash] 模型选择结果，包含 :model, :reasoning_effort, :source
      def resolve(input)
        fallback = fallback_auto_route(input[:latest_request], input[:selected_model_mode])
        return fallback if input[:abort_signal]&.aborted?

        # Simplified router - in production this would call the model client
        fallback
      end

      # 启发式模型选择，根据输入复杂度选择 flash 或 pro
      # @param input [String] 用户输入文本
      # @param current_model [String] 当前模型
      # @return [String] 选择的模型名称
      def heuristic(input, _current_model = '')
        len = input.length
        lower = input.downcase
        complex_keywords = %w[refactor architecture design debug security review audit migrate optimize rewrite implement
                              analyze]
        return AUTO_MODEL_PRO if complex_keywords.any? { |keyword| lower.include?(keyword) }
        return AUTO_MODEL_FLASH if len < 100
        return AUTO_MODEL_PRO if len > 500

        AUTO_MODEL_FLASH
      end

      # 解析自动路由推荐结果
      # @param raw [String] 原始推荐文本
      # @return [Hash, nil] 解析后的推荐结果
      def parse_recommendation(raw)
        json = extract_first_json_object(raw)
        return nil unless json

        begin
          value = JSON.parse(json)
          model = normalize_model(value['model'])
          return nil unless model

          raw_effort = [value['thinking'], value['reasoning_effort'], value['effort']]
                       .find { |effort| effort.is_a?(String) }
          reasoning_effort = raw_effort ? normalize_effort(raw_effort) : nil

          result = { model: model }
          result[:reasoning_effort] = reasoning_effort if reasoning_effort
          result
        rescue JSON::ParserError
          nil
        end
      end

      # 获取自动路由器的最近上下文
      # @param items [Array<Hash>] 历史条目
      # @param current_turn_id [String] 当前轮次 ID
      # @return [String] 上下文文本
      def recent_context(items, current_turn_id)
        rows = []
        (items.length - 1).downto(0) do |index|
          break if rows.length >= 6

          item = items[index]
          next if item[:turn_id] == current_turn_id

          text = router_text_for_item(item).strip
          next if text.empty?

          rows << "#{router_role_for_item(item)}: #{truncate_for_auto_router(text, 900)}"
        end
        rows.reverse!
        rows.empty? ? 'No prior context.' : rows.join("\n")
      end

      # 获取回退的自动路由方案
      # @param latest_request [String] 最新请求文本
      # @param selected_model_mode [String] 选择的模型模式
      # @return [Hash] 回退路由结果
      def fallback_auto_route(latest_request, selected_model_mode)
        {
          model: heuristic(latest_request, selected_model_mode),
          reasoning_effort: reasoning_heuristic(latest_request),
          source: 'heuristic'
        }
      end

      # 标准化模型名称
      # @param model [String] 模型名称
      # @return [String, nil] 标准化后的模型名称
      def normalize_model(model)
        return nil unless model.is_a?(String)

        case model.strip.downcase
        when 'deepseek-v4-pro', 'v4-pro', 'pro'
          AUTO_MODEL_PRO
        when 'deepseek-v4-flash', 'v4-flash', 'flash'
          AUTO_MODEL_FLASH
        end
      end

      # 标准化推理努力级别
      # @param effort [String] 努力级别
      # @return [String, nil] 标准化后的努力级别
      def normalize_effort(effort)
        return nil unless effort.is_a?(String)

        case effort.strip.downcase
        when 'off', 'disabled', 'none', 'false'
          'off'
        when 'low', 'minimal', 'medium', 'mid', 'high'
          'high'
        when 'max', 'maximum', 'xhigh'
          'max'
        end
      end

      # 启发式推理努力级别判断
      # @param input [String] 输入文本
      # @return [String] 推理努力级别
      def reasoning_heuristic(input)
        lower = input.downcase
        lower.include?('debug') || lower.include?('error') ? 'max' : 'high'
      end

      # 获取历史条目对应的角色名称
      # @param item [Hash] 历史条目
      # @return [String] 角色名称
      def router_role_for_item(item)
        case item[:kind]
        when 'user_message'
          'user'
        when 'tool_result'
          'tool'
        when 'compaction'
          'system'
        else
          'assistant'
        end
      end

      # 获取历史条目的文本内容
      # @param item [Hash] 历史条目
      # @return [String] 文本内容
      def router_text_for_item(item)
        case item[:kind]
        when 'user_message', 'assistant_text', 'assistant_reasoning'
          item[:text]
        when 'tool_call'
          "[tool call: #{item[:tool_name] || item[:toolName]}]"
        when 'tool_result'
          output = item[:output]
          "[tool result] #{output.is_a?(String) ? output : JSON.generate(output)}"
        when 'compaction'
          item[:summary]
        when 'approval'
          "[approval: #{item[:tool_name] || item[:toolName]}] #{item[:summary]}"
        when 'user_input'
          "[user input] #{item[:prompt]}"
        when 'review'
          "[review] #{item[:title]} #{item[:review_text] || ''}"
        when 'error'
          "[error] #{item[:message]}"
        else
          ''
        end
      end

      # 截断文本用于自动路由器
      # @param text [String] 待截断的文本
      # @param max_chars [Integer] 最大字符数
      # @return [String] 截断后的文本
      def truncate_for_auto_router(text, max_chars)
        chars = text.chars
        chars.length > max_chars ? "#{chars.first(max_chars).join}..." : text
      end

      # 从原始文本中提取第一个 JSON 对象
      # @param raw [String] 原始文本
      # @return [String, nil] 第一个 JSON 对象字符串
      def extract_first_json_object(raw)
        start_idx = raw.index('{')
        end_idx = raw.rindex('}')
        start_idx && end_idx && end_idx >= start_idx ? raw[start_idx..end_idx] : nil
      end
    end
  end
end
