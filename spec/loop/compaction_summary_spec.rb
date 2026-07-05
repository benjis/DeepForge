# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/compaction_summary'

RSpec.describe DeepForge::Loop::CompactionSummary do
  describe '.build_model_compaction_prompt' do
    let(:items) do
      [
        { kind: 'user_message', text: 'hello' },
        { kind: 'assistant_text', text: 'hi there' },
        { kind: 'tool_call', tool_name: 'read', arguments: { path: '/foo' } },
        { kind: 'tool_result', tool_name: 'read', output: 'file content' }
      ]
    end

    it 'builds a prompt with required sections' do
      prompt = described_class.build_model_compaction_prompt(
        items: items,
        heuristic_summary: 'Test summary',
        max_bytes: 96 * 1024
      )
      expect(prompt).to include('## Goal')
      expect(prompt).to include('## Completed')
      expect(prompt).to include('## Key findings')
      expect(prompt).to include('## Files & locations')
      expect(prompt).to include('## Pending')
      expect(prompt).to include('## Constraints & pins')
    end

    it 'includes conversation history' do
      prompt = described_class.build_model_compaction_prompt(
        items: items,
        heuristic_summary: '',
        max_bytes: 96 * 1024
      )
      expect(prompt).to include('[user] hello')
      expect(prompt).to include('[assistant] hi there')
    end

    it 'includes heuristic summary' do
      prompt = described_class.build_model_compaction_prompt(
        items: items,
        heuristic_summary: 'My heuristic summary',
        max_bytes: 96 * 1024
      )
      expect(prompt).to include('My heuristic summary')
    end

    it 'uses (none) for empty heuristic summary' do
      prompt = described_class.build_model_compaction_prompt(
        items: items,
        heuristic_summary: '',
        max_bytes: 96 * 1024
      )
      expect(prompt).to include('(none)')
    end

    it 'truncates to max_bytes' do
      many_items = (1..1000).map { |i| { kind: 'user_message', text: "message#{i}" * 100 } }
      prompt = described_class.build_model_compaction_prompt(
        items: many_items,
        heuristic_summary: '',
        max_bytes: 1000
      )
      # The prompt includes fixed section headers (~1KB) plus truncated transcript
      # so the total may exceed max_bytes, but transcript portion is truncated
      expect(prompt).to include('[truncated for model compaction summary]')
    end

    it 'includes (empty) when no items' do
      prompt = described_class.build_model_compaction_prompt(
        items: [],
        heuristic_summary: '',
        max_bytes: 96 * 1024
      )
      expect(prompt).to include('(empty)')
    end
  end

  describe '.summarize_compaction_with_model' do
    let(:model_client) { double('model_client') }
    let(:prefix) { ImmutablePrefixBuilder.create(system_prompt: 'test') }
    let(:signal) { double('signal', aborted?: false) }
    let(:items) { [{ kind: 'user_message', text: 'hello' }] }

    it 'returns nil when signal is aborted' do
      aborted_signal = double('signal', aborted?: true)
      result = described_class.summarize_compaction_with_model(
        thread_id: 't1', turn_id: 'r1', model: 'test',
        model_client: model_client, prefix: prefix,
        items: items, heuristic_summary: 'test',
        signal: aborted_signal
      )
      expect(result).to be_nil
    end

    it 'returns summary from model response' do
      allow(model_client).to receive(:stream) do |_opts, &blk|
        blk.call({ kind: 'assistant_text_delta', text: 'Summary of work' })
      end

      result = described_class.summarize_compaction_with_model(
        thread_id: 't1', turn_id: 'r1', model: 'test',
        model_client: model_client, prefix: prefix,
        items: items, heuristic_summary: 'test',
        signal: signal
      )
      expect(result).to eq('Summary of work')
    end

    it 'returns nil on model error' do
      allow(model_client).to receive(:stream) do |_opts, &blk|
        blk.call({ kind: 'error', message: 'failed', code: 'E001' })
      end

      result = described_class.summarize_compaction_with_model(
        thread_id: 't1', turn_id: 'r1', model: 'test',
        model_client: model_client, prefix: prefix,
        items: items, heuristic_summary: 'test',
        signal: signal
      )
      expect(result).to be_nil
    end

    it 'returns nil when response is empty' do
      allow(model_client).to receive(:stream).and_return(nil)

      result = described_class.summarize_compaction_with_model(
        thread_id: 't1', turn_id: 'r1', model: 'test',
        model_client: model_client, prefix: prefix,
        items: items, heuristic_summary: 'test',
        signal: signal
      )
      expect(result).to be_nil
    end

    it 'records usage when provided' do
      usage_recorded = []
      allow(model_client).to receive(:stream) do |_opts, &blk|
        blk.call({ kind: 'assistant_text_delta', text: 'summary' })
        blk.call({ kind: 'usage', usage: { prompt_tokens: 100 } })
      end

      described_class.summarize_compaction_with_model(
        thread_id: 't1', turn_id: 'r1', model: 'test',
        model_client: model_client, prefix: prefix,
        items: items, heuristic_summary: 'test',
        signal: signal,
        record_usage: ->(u) { usage_recorded << u }
      )
      expect(usage_recorded.length).to eq(1)
    end
  end

  describe '::DEFAULT_COMPACTION_SUMMARY_TIMEOUT_MS' do
    it 'is 15000' do
      expect(described_class::DEFAULT_COMPACTION_SUMMARY_TIMEOUT_MS).to eq(15_000)
    end
  end

  describe '::DEFAULT_COMPACTION_SUMMARY_MAX_TOKENS' do
    it 'is 1200' do
      expect(described_class::DEFAULT_COMPACTION_SUMMARY_MAX_TOKENS).to eq(1_200)
    end
  end
end
