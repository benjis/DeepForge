# frozen_string_literal: true

# 文件用途：DeepSeek 兼容模型客户端
# 使用方法：通过 HTTP 调用 DeepSeek 兼容的模型 API，支持流式和非流式响应。
#           处理工具调用、缓存命中/未命中计数、思考模式、中止信号取消等功能。
#           该客户端设计精简，使运行时的其余部分可以围绕 ModelClient 端口构建。

require 'net/http'
require 'uri'
require 'json'
require 'timeout'

require_relative 'deepseek_pricing'
require_relative 'tool_argument_repair'
require_relative 'model_error_probe'

module DeepForge
  module Adapters
    module Model
      # DeepSeek 兼容模型客户端。
      #
      # 此适配器专注于 GUI 当前使用的流式聊天补全格式。支持工具调用、
      # 缓存命中/未命中计数（当提供商报告时）和中止信号取消。
      # 客户端设计精简，使运行时的其余部分可以围绕 ModelClient 端口构建。
      class DeepseekCompatModelClient
        # 提供商标识常量
        PROVIDER = 'deepseek-compat'
        # 流式响应最大空闲超时时间（毫秒）
        DEFAULT_STREAM_IDLE_TIMEOUT_MS = 45_000

        attr_reader :provider, :model

        # 初始化 DeepSeek 兼容模型客户端
        # 参数：config - 配置哈希（含 base_url, api_key, model, headers, history_limit 等）
        def initialize(config)
          @config = config
          @model = config[:model]
          @provider = PROVIDER
        end

        # 流式获取模型响应
        # 参数：request - 请求哈希（含 system_prompt, history, tools, abort_signal 等）
        # 返回值：void（通过 yield 产出每个 chunk）
        def stream(request, &)
          return yield(error_chunk('request was aborted before start')) if request[:abort_signal]&.aborted?

          url = build_url('/v1/chat/completions')
          stream_mode = request.fetch(:stream, !@config[:non_streaming])
          body = build_request_body(request, stream_mode)
          headers = build_headers(stream_mode)

          begin
            response = post_json(url, body, headers, request[:abort_signal])
          rescue StandardError => e
            yield error_chunk("model request failed: #{e.message}")
            return
          end

          unless response.is_a?(Net::HTTPSuccess)
            text = response.body.to_s
            classified = classify_http_error(response.code.to_i, text)
            yield error_chunk(classified[:message], classified[:code])
            return
          end

          if @config[:non_streaming] || response.content_type&.include?('application/json')
            json = JSON.parse(response.body)
            materialize_non_streaming(json).each(&)
            return
          end

          stream_sse(response.body, request[:abort_signal], &)
        end

        private

        # 构建 API 请求 URL（内部方法）
        def build_url(path)
          base = @config[:base_url].gsub(%r{/+$}, '')
          "#{base}#{path}"
        end

        # 构建 HTTP 请求头（内部方法）
        def build_headers(stream)
          headers = {
            'Content-Type' => 'application/json',
            'Accept' => stream ? 'text/event-stream' : 'application/json'
          }

          headers['Authorization'] = "Bearer #{@config[:api_key]}" if @config[:api_key] && !@config[:api_key].empty?

          headers.merge(@config[:headers] || {})
        end

        # 分类 HTTP 错误并生成对应的错误 chunk（内部方法）
        def classify_http_error(status, text)
          body = text[0...500]

          if status == 429
            return {
              message: "model request was rate limited (HTTP 429): #{body}",
              code: 'rate_limited'
            }
          end

          if status >= 500 && ModelErrorProbe.deep_seek_host?(@config[:base_url])
            probe = ModelErrorProbe.probe_deep_seek_reachable(base_url: @config[:base_url])
            return {
              message: "model request failed with DeepSeek HTTP #{status}: #{body} #{probe[:message]}",
              code: probe[:reachable] ? "deepseek_http_#{status}" : 'deepseek_unreachable'
            }
          end

          {
            message: "model request failed with status #{status}: #{body}",
            code: "http_#{status}"
          }
        end

        # 构建 API 请求体（内部方法）
        def build_request_body(request, stream)
          request_model = request[:model]&.strip
          model = request_model && !request_model.empty? ? request_model : @config[:model]
          messages = collect_messages(request, model)

          body = {
            model: model,
            stream: stream,
            messages: messages
          }

          body[:max_tokens] = request[:max_tokens] if request.key?(:max_tokens)
          body[:temperature] = request[:temperature] if request.key?(:temperature)
          body[:top_p] = request[:top_p] if request.key?(:top_p)

          body[:response_format] = { type: 'json_object' } if request[:response_format] == 'json_object'

          include_thinking = !azure_openai_endpoint?(@config[:base_url])
          apply_reasoning_effort(body, request[:reasoning_effort], include_thinking: include_thinking)

          if include_thinking && !body.key?(:thinking) && thinking_producer_model?(model)
            body[:thinking] = { type: 'enabled' }
          end

          tools = normalize_tool_specs(request[:tools] || [])
          if tools.length.positive?
            body[:tools] = tools.map do |tool|
              {
                type: 'function',
                function: {
                  name: tool[:name],
                  description: tool[:description],
                  parameters: tool[:input_schema]
                }
              }
            end
          end

          body
        end

        # 收集并格式化消息列表（内部方法）
        def collect_messages(request, model)
          out = []

          out << { role: 'system', content: request[:system_prompt] } if request[:system_prompt]
          out << { role: 'system', content: request[:mode_instruction] } if request[:mode_instruction]

          (request[:context_instructions] || []).each do |instruction|
            out << { role: 'system', content: instruction } if instruction.strip
          end

          window_size = @config[:history_limit]
          history = if window_size
                      limit_history_preserving_compaction(request[:history] || [],
                                                          window_size)
                    else
                      request[:history] || []
                    end
          thinking_mode = requires_reasoning_round_trip(request[:reasoning_effort], model)

          out.concat(items_to_messages(
                       repair_model_history_items((request[:prefix] || []) + history),
                       thinking_mode
                     ))

          attach_images_to_latest_user_message(out, request[:attachments]) if request[:attachments]&.any?

          if request[:attachment_text_fallbacks]&.any?
            attach_text_fallbacks_to_latest_user_message(out, request[:attachment_text_fallbacks])
          end

          normalize_thinking_assistant_messages(heal_tool_message_pairs(out), thinking_mode)
        end

        # 将内部消息项列表转换为 API 消息格式（内部方法）
        def items_to_messages(items, thinking_mode)
          out = []
          index = 0

          while index < items.length
            item = items[index]

            if bridge_item_before_tool_call?(items, index)
              index += 1
              next
            end

            if thinking_mode && item&.dig(:kind) == 'assistant_reasoning'
              next_item = items[index + 1]
              if next_item&.dig(:kind) == 'assistant_text' && next_item[:turn_id] == item[:turn_id]
                out << {
                  role: 'assistant',
                  content: next_item[:text],
                  reasoning_content: reasoning_content_or_space(item[:text])
                }
                index += 1
              end
              index += 1
              next
            end

            if item&.dig(:kind) == 'tool_call'
              block = tool_call_block_to_messages(items, index, thinking_mode)
              if block
                out.concat(block[:messages])
                index = block[:next_index]
              else
                index += 1
              end
              next
            end

            if item&.dig(:kind) == 'tool_result'
              index += 1
              next
            end

            message = item_to_message(item, thinking_mode)
            out << message if message
            index += 1
          end

          out
        end

        # 将工具调用块转换为 API 消息格式（内部方法）
        def tool_call_block_to_messages(items, start_index, thinking_mode)
          calls = []
          index = start_index

          while index < items.length && items[index]&.dig(:kind) == 'tool_call'
            calls << items[index]
            index += 1
          end

          return nil if calls.empty?

          turn_id = calls.first[:turn_id] || ''
          expected_call_ids = Set.new(calls.map { |c| c[:call_id] })
          seen_result_ids = Set.new
          result_messages = []
          assistant_text = []
          reasoning_text = []

          bridge_index = start_index - 1
          while bridge_index >= 0
            item = items[bridge_index]
            break unless item && pre_tool_call_bridge_item?(item, turn_id)

            if item[:kind] == 'assistant_text' && item[:text]&.strip&.any?
              assistant_text.unshift(item[:text])
            elsif item[:kind] == 'assistant_reasoning' && item[:text]&.strip&.any?
              reasoning_text.unshift(item[:text])
            end

            bridge_index -= 1
          end

          saw_result = false
          while index < items.length
            item = items[index]
            break unless item

            if item[:kind] == 'tool_result'
              saw_result = true
              if expected_call_ids.include?(item[:call_id]) && !seen_result_ids.include?(item[:call_id])
                seen_result_ids.add(item[:call_id])
                result_messages << tool_result_to_message(item)
              end
              index += 1
              next
            end

            if tool_result_bridge_item?(item, turn_id: turn_id, saw_result: saw_result)
              unless saw_result
                if item[:kind] == 'assistant_text' && item[:text]&.strip&.any?
                  assistant_text << item[:text]
                elsif item[:kind] == 'assistant_reasoning' && item[:text]&.strip&.any?
                  reasoning_text << item[:text]
                end
              end
              index += 1
              next
            end

            break
          end

          return nil unless expected_call_ids.all? { |id| seen_result_ids.include?(id) }

          {
            messages: [
              {
                role: 'assistant',
                content: assistant_text.any? ? assistant_text.join("\n") : '',
                **(thinking_mode ? { reasoning_content: reasoning_content_or_space(reasoning_text.join("\n")) } : {}),
                tool_calls: calls.map { |call| tool_call_to_wire(call) }
              },
              *result_messages
            ],
            next_index: index
          }
        end

        # 将内部工具调用项转换为 API 线路格式（内部方法）
        def tool_call_to_wire(item)
          {
            id: item[:call_id],
            type: 'function',
            function: {
              name: item[:tool_name],
              arguments: JSON.generate(item[:arguments])
            }
          }
        end

        # 将内部工具结果项转换为 API 消息格式（内部方法）
        def tool_result_to_message(item)
          {
            role: 'tool',
            content: tool_result_content(item[:output]),
            tool_call_id: item[:call_id]
          }
        end

        # 将单个内部消息项转换为 API 消息格式（内部方法）
        def item_to_message(item, thinking_mode)
          case item[:kind]
          when 'user_message'
            { role: 'user', content: item[:text] }
          when 'assistant_text'
            {
              role: 'assistant',
              content: item[:text],
              **(thinking_mode ? { reasoning_content: ' ' } : {})
            }
          when 'assistant_reasoning'
            nil
          when 'tool_call'
            {
              role: 'assistant',
              content: '',
              **(thinking_mode ? { reasoning_content: ' ' } : {}),
              tool_calls: [tool_call_to_wire(item)]
            }
          when 'tool_result'
            tool_result_to_message(item)
          when 'compaction'
            if item[:replaced_tokens]&.positive?
              { role: 'system', content: "Conversation summary from earlier turns:\n#{item[:summary]}" }
            end
          when 'review'
            if item[:status] == 'completed' && item[:review_text]&.strip&.any?
              { role: 'system', content: "Code review result from an earlier turn:\n#{item[:review_text]}" }
            end
          when 'approval', 'user_input', 'error'
            nil
          end
        end

        # 解析 SSE 流式响应并产出 chunk（内部方法）
        def stream_sse(body, signal, &block)
          ''.dup
          buffer = ''.dup
          pending_arguments = {}
          usage = nil
          text_accumulator = ''.dup
          reasoning_accumulator = ''.dup
          finish_reason = nil
          normalize_stream_idle_timeout_ms(@config[:stream_idle_timeout_ms])

          begin
            body.each_line do |line|
              break if signal&.aborted?

              buffer << line
              while (boundary = buffer.index("\n\n"))
                frame = buffer[0...boundary]
                buffer = buffer[(boundary + 2)..]

                data_lines = frame.split("\n")
                                  .select { |l| l.start_with?('data:') }
                                  .map { |l| l[5..].strip }
                                  .join

                next if data_lines.empty?

                if data_lines == '[DONE]'
                  finish_reason ||= 'stop'
                  break
                end

                begin
                  payload = JSON.parse(data_lines)
                rescue JSON::ParserError
                  next
                end

                result = consume_stream_payload(
                  payload,
                  pending_arguments,
                  text_accumulator,
                  reasoning_accumulator
                )

                text_accumulator = result[:text]
                reasoning_accumulator = result[:reasoning]
                usage = result[:usage] if result[:usage]
                finish_reason = result[:finish_reason] if result[:finish_reason]
                result[:chunks].each(&block)
              end

              break if %w[stop tool_calls length].include?(finish_reason)
            end
          rescue StandardError => e
            yield error_chunk("model stream read failed: #{e.message}", 'stream_read_error')
            return
          end

          if signal&.aborted?
            yield error_chunk('request was aborted')
            return
          end

          yield({ kind: 'usage', usage: usage }) if usage

          stop_reason = case finish_reason
                        when 'tool_calls' then 'tool_calls'
                        when 'length' then 'length'
                        when 'error' then 'error'
                        else 'stop'
                        end

          yield({ kind: 'completed', stop_reason: stop_reason })
        end

        # 消费单个 SSE 事件负载，更新累积状态并产出 chunk（内部方法）
        def consume_stream_payload(payload, pending_arguments, text_accumulator, reasoning_accumulator)
          chunks = []
          text = text_accumulator
          reasoning = reasoning_accumulator
          finish_reason = nil
          usage = nil

          choice = payload.dig('choices', 0)
          if choice.is_a?(Hash)
            delta = choice['delta']
            if delta.is_a?(Hash)
              content = delta['content']
              if content.is_a?(String) && !content.empty?
                text += content
                chunks << { kind: 'assistant_text_delta', text: content }
              end

              reasoning_content = delta['reasoning_content'] || delta['reasoning']
              if reasoning_content.is_a?(String) && !reasoning_content.empty?
                reasoning += reasoning_content
                chunks << { kind: 'assistant_reasoning_delta', text: reasoning_content }
              end

              tool_calls = delta['tool_calls']
              if tool_calls.is_a?(Array)
                tool_calls.each do |call|
                  id = resolve_tool_call_delta_id(call, pending_arguments)
                  existing = pending_arguments[id] || {
                    index: numeric_index(call['index']),
                    name: nil,
                    arguments: ''
                  }

                  resolved_index = numeric_index(call['index'])
                  existing[:index] = resolved_index if resolved_index
                  existing[:name] = call.dig('function', 'name') if call.dig('function', 'name')

                  if call.dig('function', 'arguments').is_a?(String)
                    existing[:arguments] += call.dig('function', 'arguments')
                    chunks << {
                      kind: 'tool_call_delta',
                      call_id: id,
                      tool_name: existing[:name],
                      arguments_delta: call.dig('function', 'arguments')
                    }
                  end

                  pending_arguments[id] = existing
                end
              end
            end

            finish_reason = choice['finish_reason'] if choice['finish_reason'].is_a?(String)
          end

          usage_payload = payload['usage']
          usage = map_usage(usage_payload) if usage_payload.is_a?(Hash)

          if finish_reason == 'tool_calls' && !pending_arguments.empty?
            pending_arguments.each do |call_id, value|
              next unless value[:name]

              args = parse_tool_arguments(value[:arguments])
              chunks << {
                kind: 'tool_call_complete',
                call_id: call_id,
                tool_name: value[:name],
                arguments: args
              }
            end
            pending_arguments.clear
          end

          {
            chunks: chunks,
            text: text,
            reasoning: reasoning,
            finish_reason: finish_reason,
            usage: usage
          }
        end

        # 将非流式 JSON 响应转换为 chunk 序列（内部方法）
        def materialize_non_streaming(payload)
          return enum_for(:materialize_non_streaming, payload) unless block_given?

          choice = payload.dig('choices', 0)
          unless choice
            yield error_chunk('model response contained no choices')
            return
          end

          text = choice.dig('message', 'content').is_a?(String) ? choice.dig('message', 'content') : ''
          reasoning = reasoning_from_message(choice['message'])

          yield({ kind: 'assistant_reasoning_delta', text: reasoning }) if reasoning
          yield({ kind: 'assistant_text_delta', text: text }) if text

          tool_calls = choice.dig('message', 'tool_calls')
          if tool_calls.is_a?(Array)
            tool_calls.each do |call|
              args = parse_tool_arguments(call.dig('function', 'arguments') || '{}')
              yield({
                kind: 'tool_call_complete',
                call_id: call['id'],
                tool_name: call.dig('function', 'name'),
                arguments: args
              })
            end
          end

          yield({ kind: 'usage', usage: map_usage(payload['usage']) }) if payload['usage']

          stop_reason = case choice['finish_reason']
                        when 'tool_calls' then 'tool_calls'
                        when 'length' then 'length'
                        when 'error' then 'error'
                        else 'stop'
                        end

          yield({ kind: 'completed', stop_reason: stop_reason })
        end

        # 将原始 usage 数据映射为标准格式（内部方法）
        def map_usage(usage)
          prompt_tokens = (usage['prompt_tokens'] || usage['prompt_eval_count'] || 0).to_i
          completion_tokens = (usage['completion_tokens'] || usage['eval_count'] || 0).to_i
          total_tokens = (usage['total_tokens'] || (prompt_tokens + completion_tokens)).to_i

          prompt_details = usage['prompt_tokens_details']
          native_hit = (usage['prompt_cache_hit_tokens'] || 0).to_i
          native_miss = (usage['prompt_cache_miss_tokens'] || 0).to_i
          has_native_cache = native_hit.positive? || native_miss.positive?

          cached_tokens = prompt_details.is_a?(Hash) ? (prompt_details['cached_tokens'] || 0).to_i : 0
          cache_read = (usage['cache_read_input_tokens'] || 0).to_i
          (usage['cache_creation_input_tokens'] || 0).to_i

          cache_hit = if has_native_cache
                        native_hit
                      elsif cached_tokens.positive?
                        cached_tokens
                      else
                        cache_read
                      end

          cache_miss = has_native_cache ? native_miss : [prompt_tokens - cache_hit, 0].max
          cache_total = cache_hit + cache_miss
          cache_hit_rate = cache_total.zero? ? nil : cache_hit.to_f / cache_total

          estimated_cost = DeepseekPricing.estimate_deepseek_cost(
            model: @config[:model],
            cache_hit_tokens: cache_hit,
            cache_miss_tokens: cache_miss,
            output_tokens: completion_tokens
          )

          estimated_savings = DeepseekPricing.estimate_deepseek_cache_savings(
            model: @config[:model],
            cache_hit_tokens: cache_hit
          )

          reported_cost_usd = (usage['cost_usd'] || usage['costUsd']).to_f
          reported_cost_cny = (usage['cost_cny'] || usage['costCny']).to_f

          {
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: total_tokens,
            cached_tokens: if cache_hit.positive?
                             cache_hit
                           else
                             (cached_tokens.positive? ? cached_tokens : cache_read)
                           end,
            cache_hit_tokens: cache_hit,
            cache_miss_tokens: cache_miss,
            cache_hit_rate: cache_hit_rate,
            turns: 1,
            cost_usd: reported_cost_usd.finite? ? reported_cost_usd : estimated_cost&.dig(:cost_usd),
            cost_cny: reported_cost_cny.finite? ? reported_cost_cny : estimated_cost&.dig(:cost_cny),
            cache_savings_usd: estimated_savings&.dig(:cost_usd),
            cache_savings_cny: estimated_savings&.dig(:cost_cny)
          }
        end

        # 解析工具调用参数 JSON（内部方法，使用 ToolArgumentRepair 修复）
        def parse_tool_arguments(raw)
          ToolArgumentRepair.repair_tool_arguments(raw)[:arguments]
        end

        # 从模型消息中提取思考内容（内部方法）
        def reasoning_from_message(message)
          return '' unless message

          value = message['reasoning_content'] || message['reasoning']
          value.is_a?(String) ? value : ''
        end

        # 将工具结果输出转换为字符串（内部方法）
        def tool_result_content(output)
          return output if output.is_a?(String)

          output.to_json
        end

        # 如果思考内容为空则返回空格（内部方法，满足 API 要求）
        def reasoning_content_or_space(text)
          text.strip.any? ? text : ' '
        end

        # 判断消息项是否为工具调用前的桥接项（内部方法）
        def pre_tool_call_bridge_item?(item, turn_id)
          return false unless item[:turn_id] == turn_id

          %w[assistant_reasoning assistant_text].include?(item[:kind])
        end

        # 判断消息项是否为工具调用前的桥接项（从索引角度）（内部方法）
        def bridge_item_before_tool_call?(items, index)
          item = items[index]
          return false unless item && %w[assistant_reasoning assistant_text].include?(item[:kind])

          cursor = index + 1
          while cursor < items.length
            nxt = items[cursor]
            return false unless nxt

            if %w[assistant_reasoning assistant_text].include?(nxt[:kind])
              return false unless nxt[:turn_id] == item[:turn_id]

              cursor += 1
              next
            end

            return nxt[:kind] == 'tool_call' && nxt[:turn_id] == item[:turn_id]
          end

          false
        end

        # 判断消息项是否为工具结果后的桥接项（内部方法）
        def tool_result_bridge_item?(item, turn_id:, saw_result:)
          return false unless item[:turn_id] == turn_id
          return false unless %w[assistant_reasoning assistant_text].include?(item[:kind])
          return false if saw_result

          true
        end

        # 解析工具调用增量中的 ID（内部方法，处理索引映射）
        def resolve_tool_call_delta_id(call, pending)
          index = numeric_index(call['index'])
          existing_by_index = find_pending_tool_call_id_by_index(pending, index)

          if call['id']
            if existing_by_index && existing_by_index != call['id']
              existing = pending.delete(existing_by_index)
              pending[call['id']] = existing if existing
            end
            return call['id']
          end

          existing_by_index || "call_#{pending.size + 1}"
        end

        # 根据索引查找待处理的工具调用 ID（内部方法）
        def find_pending_tool_call_id_by_index(pending, index)
          return nil unless index

          pending.each do |call_id, value|
            return call_id if value[:index] == index
          end

          nil
        end

        # 将索引值转换为整数（内部方法）
        def numeric_index(index)
          index.is_a?(Integer) && index >= 0 ? index : nil
        end

        # 判断是否启用了思考模式（内部方法）
        def thinking_mode?(effort)
          normalized = effort&.strip&.downcase
          return false unless normalized

          !%w[off disabled none false].include?(normalized)
        end

        # 判断是否需要推理往返（内部方法）
        def requires_reasoning_round_trip?(effort, model)
          thinking_mode?(effort) || thinking_producer_model?(model)
        end

        # 判断模型是否支持思考输出（内部方法）
        def thinking_producer_model?(model)
          normalized = normalize_model_id(model)
          return false if normalized.empty?

          normalized == 'deepseek-v4-pro' ||
            normalized == 'deepseek-v4-flash' ||
            normalized.include?('deepseek-reasoner') ||
            normalized.end_with?('/deepseek-v4-pro') ||
            normalized.end_with?('/deepseek-v4-flash')
        end

        # 标准化模型 ID（内部方法）
        def normalize_model_id(model)
          model&.strip&.downcase || ''
        end

        # 判断是否为 Azure OpenAI 端点（内部方法）
        def azure_openai_endpoint?(base_url)
          uri = URI.parse(base_url)
          host = uri.hostname&.downcase || ''
          host.end_with?('.openai.azure.com') || host.end_with?('.cognitiveservices.azure.com')
        rescue URI::InvalidURIError
          base_url.match?(/\.openai\.azure\.com|\.cognitiveservices\.azure\.com/i)
        end

        # 递归标准化哈希/数组值（排序键）（内部方法）
        def canonicalize(value)
          if value.is_a?(Array)
            value.map { |v| canonicalize(v) }
          elsif value.is_a?(Hash)
            value.sort.to_h.transform_values { |v| canonicalize(v) }
          else
            value
          end
        end

        # 标准化工具规格列表（内部方法）
        def normalize_tool_specs(tools)
          tools.map do |tool|
            {
              name: tool[:name],
              description: tool[:description],
              input_schema: canonicalize(tool[:input_schema]) || {}
            }
          end.sort_by { |t| t[:name] }
        end

        # 应用推理努力级别到请求体（内部方法）
        def apply_reasoning_effort(body, effort, include_thinking: true)
          normalized = effort&.strip&.downcase
          return unless normalized

          case normalized
          when 'off', 'disabled', 'none', 'false'
            body[:thinking] = { type: 'disabled' } if include_thinking
          when 'low', 'minimal', 'medium', 'mid', 'high'
            body[:reasoning_effort] = 'high'
            body[:thinking] = { type: 'enabled' } if include_thinking
          when 'max', 'maximum', 'xhigh'
            body[:reasoning_effort] = 'max'
            body[:thinking] = { type: 'enabled' } if include_thinking
          end
        end

        # 修复消息列表中不匹配的工具调用和工具结果对（内部方法）
        def heal_tool_message_pairs(messages)
          healed = []
          i = 0

          while i < messages.length
            message = messages[i]

            if message[:role] == 'tool'
              i += 1
              next
            end

            if message[:role] == 'assistant' && message[:tool_calls]&.any?
              expected_ids = Set.new(message[:tool_calls].map { |c| c[:id] })
              tool_results = []
              j = i + 1

              while j < messages.length && messages[j][:role] == 'tool'
                tool_result = messages[j]
                if tool_result[:tool_call_id] && expected_ids.include?(tool_result[:tool_call_id])
                  tool_results << tool_result
                end
                j += 1
              end

              seen_ids = Set.new(tool_results.map { |tr| tr[:tool_call_id] })
              if expected_ids.all? { |id| seen_ids.include?(id) }
                healed << message
                healed.concat(tool_results)
              end

              i = j
              next
            end

            healed << message
            i += 1
          end

          healed
        end

        # 标准化思考模式下的助手消息（确保 reasoning_content 字段存在）（内部方法）
        def normalize_thinking_assistant_messages(messages, thinking_mode)
          return messages unless thinking_mode

          messages.map do |message|
            next message unless message[:role] == 'assistant'

            msg = message.dup
            msg[:content] = '' if msg[:content].nil?

            if !msg.key?(:reasoning_content) || msg[:reasoning_content].nil? || msg[:reasoning_content].strip.none?
              msg[:reasoning_content] = ' '
            end

            msg
          end
        end

        # 将图片附件附加到最后一条用户消息（内部方法）
        def attach_images_to_latest_user_message(messages, attachments)
          (messages.length - 1).downto(0) do |index|
            message = messages[index]
            next unless message[:role] == 'user'

            parts = []
            parts << { type: 'text', text: message[:content] } if message[:content].is_a?(String) && message[:content]

            attachments.each do |attachment|
              parts << {
                type: 'image_url',
                image_url: { url: "data:#{attachment[:mime_type]};base64,#{attachment[:data_base64]}" }
              }
            end

            message[:content] = parts
            return
          end
        end

        # 将文本回退内容附加到最后一条用户消息（内部方法）
        def attach_text_fallbacks_to_latest_user_message(messages, attachments)
          text = attachments.map { |a| format_attachment_text_fallback(a) }.join("\n\n")

          (messages.length - 1).downto(0) do |index|
            message = messages[index]
            next unless message[:role] == 'user'

            if message[:content].is_a?(String)
              message[:content] = message[:content].empty? ? text : "#{message[:content]}\n\n#{text}"
              return
            end

            if message[:content].is_a?(Array)
              message[:content] << { type: 'text', text: text }
              return
            end

            message[:content] = text
            return
          end
        end

        # 格式化附件的文本回退内容（内部方法）
        def format_attachment_text_fallback(attachment)
          [
            '[Attached image as base64 text]',
            "Name: #{attachment[:name]}",
            "MIME: #{attachment[:mime_type]}",
            "Dimensions: #{format_attachment_dimensions(attachment)}",
            "Bytes: #{attachment[:byte_size]}",
            'Base64:',
            '```base64',
            attachment[:data_base64],
            '```',
            '[/Attached image]'
          ].join("\n")
        end

        # 格式化附件的尺寸信息（内部方法）
        def format_attachment_dimensions(attachment)
          if attachment[:width] && attachment[:height]
            "#{attachment[:width]}x#{attachment[:height]}"
          else
            'unknown'
          end
        end

        # 限制历史消息数量，同时保留压缩摘要（内部方法）
        def limit_history_preserving_compaction(history, window_size)
          return history if history.length <= window_size

          window_start = history.length - window_size
          limited = history[window_start..]

          return limited if limited.any? { |i| i[:kind] == 'compaction' && i[:replaced_tokens]&.positive? }

          (window_start - 1).downto(0) do |index|
            item = history[index]
            next unless item[:kind] == 'compaction' && item[:replaced_tokens]&.positive?

            return window_size <= 1 ? [item] : [item, *history[-(window_size - 1)..]]
          end

          limited
        end

        # 发送 JSON POST 请求（内部方法）
        def post_json(url, body, headers, _signal = nil)
          uri = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')

          request = Net::HTTP::Post.new(uri.request_uri)
          headers.each { |k, v| request[k] = v }
          request.body = JSON.generate(body)

          http.request(request)
        end

        # 标准化流式空闲超时时间（内部方法）
        def normalize_stream_idle_timeout_ms(value)
          return DEFAULT_STREAM_IDLE_TIMEOUT_MS unless value
          return DEFAULT_STREAM_IDLE_TIMEOUT_MS unless value.is_a?(Numeric) && value.finite?

          [0, value.to_i].max
        end

        # 创建错误类型的 chunk（内部方法）
        def error_chunk(message, code = nil)
          chunk = { kind: 'error', message: message }
          chunk[:code] = code if code
          chunk
        end

        # 修复模型历史消息项（内部方法，默认透传）
        def repair_model_history_items(items)
          items
        end
      end
    end
  end
end
