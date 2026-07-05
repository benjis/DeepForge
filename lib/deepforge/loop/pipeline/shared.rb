# frozen_string_literal: true

require 'securerandom'

module DeepForge
  module Loop
    class Pipeline
      module Shared
        PIPELINE_STAGE_LABELS = {
          setup: 'Setup',
          pre_start: 'Pre-Start',
          post_start: 'Post-Start',
          input_received: 'Input Received',
          input_cached: 'Input Cached',
          input_routed: 'Input Routed',
          input_compressed: 'Input Compressed',
          input_remembered: 'Input Remembered',
          pre_send: 'Pre-Send',
          post_send: 'Post-Send',
          response_received: 'Response Received'
        }.freeze

        def now_ms
          @opts[:now_ms]&.call || (Time.now.to_f * 1000).to_i
        end

        def now_iso
          @opts[:now_iso]&.call || Time.now.utc.strftime('%FT%TZ')
        end

        def next_id(prefix)
          @opts[:ids]&.next(prefix) || "#{prefix}_#{SecureRandom.hex(8)}"
        end

        def escape_xml_text(value)
          value.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
        end

        def record_pipeline_stage(thread_id, turn_id, stage, details = nil)
          event = {
            kind: 'pipeline_stage',
            thread_id: thread_id,
            turn_id: turn_id,
            stage: stage,
            label: PIPELINE_STAGE_LABELS[stage]
          }
          event[:details] = details if details && !details.empty?
          @opts[:events]&.record(event)
        end

        def normalize_approval_policy(value)
          case value
          when 'never', 'auto', 'suggest', 'untrusted'
            value
          else
            'on-request'
          end
        end

        def prefix_volatility_stage_details(findings)
          return nil if findings.empty?

          kinds = findings.map { |f| f[:kind] }.uniq.sort
          fields = findings.map { |f| f[:field] }.uniq.sort
          {
            prefix_volatile_token_count: findings.length,
            prefix_volatile_token_kinds: kinds,
            prefix_volatile_fields: fields,
            no_regex_detector: true
          }
        end

        def make_error_item(id, thread_id, turn_id, message, code)
          {
            id: id, turn_id: turn_id, thread_id: thread_id,
            kind: 'error', message: message, code: code
          }
        end

        def make_assistant_text_item(id, turn_id, thread_id, text, status)
          { id: id, turn_id: turn_id, thread_id: thread_id, kind: 'assistant_text', text: text, status: status }
        end

        def make_assistant_reasoning_item(id, turn_id, thread_id, text, status)
          { id: id, turn_id: turn_id, thread_id: thread_id, kind: 'assistant_reasoning', text: text, status: status }
        end

        def make_tool_call_item(id, turn_id, thread_id, call_id, tool_name, tool_kind, arguments, notes = [])
          item = {
            id: id, turn_id: turn_id, thread_id: thread_id,
            kind: 'tool_call', call_id: call_id, tool_name: tool_name,
            tool_kind: tool_kind, arguments: arguments
          }
          item[:summary] = "Repaired tool arguments: #{notes.join('; ')}" if notes.any?
          item
        end

        def make_tool_result_item(id, turn_id, thread_id, call_id, tool_name, tool_kind, output, is_error)
          {
            id: id, turn_id: turn_id, thread_id: thread_id,
            kind: 'tool_result', call_id: call_id, tool_name: tool_name,
            tool_kind: tool_kind, output: output, is_error: is_error
          }
        end

        def fail_turn(thread_id, turn_id, message)
          @opts[:turns]&.finish_turn(thread_id: thread_id, turn_id: turn_id, status: 'failed', error: message)
        end

        def tool_kinds
          @tool_kinds ||= (@opts[:tools] || []).to_h { |tool| [tool[:name], tool[:tool_kind]] }
        end
      end
    end
  end
end
