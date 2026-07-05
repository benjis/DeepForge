# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/session_summary'

RSpec.describe DeepForge::Loop::SessionSummary do
  describe '.build_session_transcript' do
    it 'formats user messages' do
      items = [{ kind: 'user_message', text: 'hello' }]
      result = described_class.build_session_transcript(items, 96 * 1024)
      expect(result).to include('[user] hello')
    end

    it 'formats assistant text' do
      items = [{ kind: 'assistant_text', text: 'hi there' }]
      result = described_class.build_session_transcript(items, 96 * 1024)
      expect(result).to include('[assistant] hi there')
    end

    it 'formats tool calls' do
      items = [{ kind: 'tool_call', tool_name: 'read', summary: 'read file' }]
      result = described_class.build_session_transcript(items, 96 * 1024)
      expect(result).to include('[tool_call:read]')
    end

    it 'formats tool results' do
      items = [{ kind: 'tool_result', tool_name: 'bash', output: 'done' }]
      result = described_class.build_session_transcript(items, 96 * 1024)
      expect(result).to include('[tool_result:bash]')
    end

    it 'formats error items' do
      items = [{ kind: 'error', message: 'something went wrong', code: 'E001' }]
      result = described_class.build_session_transcript(items, 96 * 1024)
      expect(result).to include('[error:E001]')
    end

    it 'formats compaction with replaced_tokens' do
      items = [{ kind: 'compaction', summary: 'earlier work', replaced_tokens: 100 }]
      result = described_class.build_session_transcript(items, 96 * 1024)
      expect(result).to include('[earlier summary]')
    end

    it 'skips compaction with 0 replaced_tokens' do
      items = [{ kind: 'compaction', summary: 'noop', replaced_tokens: 0 }]
      result = described_class.build_session_transcript(items, 96 * 1024)
      expect(result).not_to include('noop')
    end

    it 'returns empty for empty items' do
      result = described_class.build_session_transcript([], 96 * 1024)
      expect(result.strip).to eq('')
    end

    it 'truncates to max_bytes' do
      items = (1..100).map { |i| { kind: 'user_message', text: "message#{i}" * 100 } }
      result = described_class.build_session_transcript(items, 1000)
      expect(result.bytesize).to be <= 2000
    end
  end

  describe '.generate_session_summary' do
    let(:model_client) { double('model_client') }
    let(:signal) { double('signal', aborted?: false) }

    before do
      unless Concurrent::Promises.respond_to?(:reschedule_event)
        Concurrent::Promises.define_singleton_method(:reschedule_event) do |*_args, &blk|
          blk&.call
          Object.new.tap { |o| def o.cancel; end }
        end
      end
    end

    it 'returns nil when abort_signal is aborted' do
      aborted_signal = double('signal', aborted?: true)
      result = described_class.generate_session_summary(
        thread_id: 't1', model_client: model_client, model: 'test',
        items: [], abort_signal: aborted_signal
      )
      expect(result).to be_nil
    end

    it 'returns nil for empty transcript' do
      result = described_class.generate_session_summary(
        thread_id: 't1', model_client: model_client, model: 'test',
        items: []
      )
      expect(result).to be_nil
    end

    it 'returns summary from model response' do
      allow(model_client).to receive(:stream).and_return([{ kind: 'assistant_text_delta',
                                                            text: 'User discussed code architecture' }])

      items = [{ kind: 'user_message', text: 'help me design a system' }]
      result = described_class.generate_session_summary(
        thread_id: 't1', model_client: model_client, model: 'test',
        items: items
      )
      expect(result).to eq('User discussed code architecture')
    end

    it 'returns nil on model error' do
      allow(model_client).to receive(:stream).and_return([{ kind: 'error', message: 'failed' }])

      items = [{ kind: 'user_message', text: 'hello' }]
      result = described_class.generate_session_summary(
        thread_id: 't1', model_client: model_client, model: 'test',
        items: items
      )
      expect(result).to be_nil
    end

    it 'returns nil on exception' do
      allow(model_client).to receive(:stream).and_raise('boom')

      items = [{ kind: 'user_message', text: 'hello' }]
      result = described_class.generate_session_summary(
        thread_id: 't1', model_client: model_client, model: 'test',
        items: items
      )
      expect(result).to be_nil
    end

    it 'normalizes whitespace in summary' do
      allow(model_client).to receive(:stream).and_return([{ kind: 'assistant_text_delta',
                                                            text: 'User   discussed  code' }])

      items = [{ kind: 'user_message', text: 'help me' }]
      result = described_class.generate_session_summary(
        thread_id: 't1', model_client: model_client, model: 'test',
        items: items
      )
      expect(result).to eq('User discussed code')
    end

    it 'returns nil when summary is empty after sanitization' do
      allow(model_client).to receive(:stream).and_return([{ kind: 'assistant_text_delta', text: '   ' }])

      items = [{ kind: 'user_message', text: 'hello' }]
      result = described_class.generate_session_summary(
        thread_id: 't1', model_client: model_client, model: 'test',
        items: items
      )
      expect(result).to be_nil
    end
  end

  describe '::DEFAULT_SESSION_SUMMARY_TIMEOUT_MS' do
    it 'is 20000' do
      expect(described_class::DEFAULT_SESSION_SUMMARY_TIMEOUT_MS).to eq(20_000)
    end
  end

  describe '::DEFAULT_SESSION_SUMMARY_MAX_TOKENS' do
    it 'is 400' do
      expect(described_class::DEFAULT_SESSION_SUMMARY_MAX_TOKENS).to eq(400)
    end
  end

  describe '::SESSION_SUMMARY_SYSTEM_PROMPT' do
    it 'is a non-empty string' do
      expect(described_class::SESSION_SUMMARY_SYSTEM_PROMPT).to be_a(String)
      expect(described_class::SESSION_SUMMARY_SYSTEM_PROMPT).not_to be_empty
    end
  end
end
