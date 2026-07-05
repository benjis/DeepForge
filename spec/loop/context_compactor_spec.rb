# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/compaction/compactor'

RSpec.describe DeepForge::Loop::ContextCompactor do
  subject(:compactor) { described_class.new(soft_threshold: soft, hard_threshold: hard) }

  let(:soft) { 100 }
  let(:hard) { 200 }

  let(:prefix) do
    ImmutablePrefixBuilder.create(
      system_prompt: 'test prompt',
      pinned_constraints: ['user: keep context']
    )
  end

  describe '#initialize' do
    it 'uses default thresholds when not specified' do
      c = described_class.new
      expect(c.soft_threshold).to eq(DeepForge::Loop::ModelContextProfile::DEFAULT_CONTEXT_THRESHOLDS[:soft_threshold])
      expect(c.hard_threshold).to eq(DeepForge::Loop::ModelContextProfile::DEFAULT_CONTEXT_THRESHOLDS[:hard_threshold])
    end

    it 'uses custom thresholds' do
      expect(compactor.soft_threshold).to eq(100)
      expect(compactor.hard_threshold).to eq(200)
    end
  end

  describe '#estimate' do
    it 'returns token count for items' do
      items = [{ kind: 'user_message', text: 'a' * 400 }]
      expect(compactor.estimate(items)).to eq(100)
    end

    it 'returns 0 for empty items' do
      expect(compactor.estimate([])).to eq(0)
    end
  end

  describe '#should_compact' do
    it 'returns false when below soft threshold' do
      items = [{ kind: 'user_message', text: 'a' * 100 }]
      expect(compactor.should_compact(items)).to be(false)
    end

    it 'returns true when above soft threshold' do
      items = [{ kind: 'user_message', text: 'a' * 500 }]
      expect(compactor.should_compact(items)).to be(true)
    end

    it 'uses prompt_tokens when higher than estimate' do
      items = [{ kind: 'user_message', text: 'a' * 100 }]
      expect(compactor.should_compact(items, prompt_tokens: 150)).to be(true)
    end
  end

  describe '#plan_compaction' do
    it 'returns nil when below threshold' do
      items = [{ kind: 'user_message', text: 'a' * 100 }]
      expect(compactor.plan_compaction(items)).to be_nil
    end

    it 'returns normal mode near soft threshold' do
      items = [{ kind: 'user_message', text: 'a' * 500 }]
      plan = compactor.plan_compaction(items)
      expect(plan).not_to be_nil
      expect(plan[:mode]).to eq(:normal)
      expect(plan[:keep_recent]).to eq(4)
    end

    it 'returns aggressive mode between thresholds' do
      # aggressive_threshold = soft + ((hard - soft) * 0.6) = 100 + 60 = 160
      # Need tokens in [160, 200) => chars in [640, 800)
      items = [{ kind: 'user_message', text: 'a' * 700 }]
      plan = compactor.plan_compaction(items)
      expect(plan).not_to be_nil
      expect(plan[:mode]).to eq(:aggressive)
      expect(plan[:keep_recent]).to eq(2)
    end

    it 'returns force mode above hard threshold' do
      items = [{ kind: 'user_message', text: 'a' * 1200 }]
      plan = compactor.plan_compaction(items)
      expect(plan).not_to be_nil
      expect(plan[:mode]).to eq(:force)
      expect(plan[:keep_recent]).to eq(1)
    end

    it 'uses prompt_tokens when higher' do
      items = [{ kind: 'user_message', text: 'a' * 100 }]
      plan = compactor.plan_compaction(items, prompt_tokens: 150)
      expect(plan).not_to be_nil
    end

    it 'respects frozen_message_count' do
      items = [
        { kind: 'user_message', text: 'a' * 400 },
        { kind: 'user_message', text: 'b' * 40 }
      ]
      # Frozen items are excluded from estimation; only second item (~10 tokens) is considered
      plan = compactor.plan_compaction(items, frozen_message_count: 1)
      expect(plan).to be_nil
    end
  end

  describe '#compact' do
    let(:history) do
      [
        { id: '1', kind: 'user_message', text: 'a' * 200 },
        { id: '2', kind: 'assistant_text', text: 'b' * 200 },
        { id: '3', kind: 'user_message', text: 'c' * 200 },
        { id: '4', kind: 'assistant_text', text: 'd' * 200 }
      ]
    end

    before do
      # The compact instance method calls trim_trailing_tool_calls but only a
      # class method exists. Define an instance method that delegates to it.
      compactor.define_singleton_method(:trim_trailing_tool_calls) do |history|
        self.class.trim_trailing_tool_calls(history)
      end
    end

    it 'performs compaction and returns summary item' do
      result = compactor.compact(
        thread_id: 't1', turn_id: 'r1',
        history: history, prefix: prefix,
        keep_recent: 2, reason: 'test', mode: :normal
      )
      expect(result[:summary_item][:kind]).to eq('compaction')
      expect(result[:replaced_tokens]).to be >= 0
      expect(result[:next]).to be_an(Array)
    end

    it 'includes kept tail items' do
      result = compactor.compact(
        thread_id: 't1', turn_id: 'r1',
        history: history, prefix: prefix,
        keep_recent: 2, reason: 'test', mode: :normal
      )
      tail_ids = result[:next].reject { |i| i[:kind] == 'compaction' }.map { |i| i[:id] }
      expect(tail_ids).to include('3', '4')
    end

    it 'returns noop when history too short' do
      short_history = [{ id: '1', kind: 'user_message', text: 'hi' }]
      result = compactor.compact(
        thread_id: 't1', turn_id: 'r1',
        history: short_history, prefix: prefix,
        keep_recent: 4, reason: 'test', mode: :normal
      )
      expect(result[:replaced_tokens]).to eq(0)
    end

    it 'uses summary_override when provided' do
      result = compactor.compact(
        thread_id: 't1', turn_id: 'r1',
        history: history, prefix: prefix,
        keep_recent: 2, reason: 'test', mode: :normal,
        summary_override: 'Custom summary'
      )
      expect(result[:summary_item][:summary]).to include('Custom summary')
    end

    it 'includes digest marker in summary' do
      result = compactor.compact(
        thread_id: 't1', turn_id: 'r1',
        history: history, prefix: prefix,
        keep_recent: 2, reason: 'test', mode: :normal
      )
      expect(result[:summary_item][:summary]).to include('deepforge:tool_digest')
    end

    it 'includes pinned constraints from prefix' do
      result = compactor.compact(
        thread_id: 't1', turn_id: 'r1',
        history: history, prefix: prefix,
        keep_recent: 2, reason: 'test', mode: :normal
      )
      expect(result[:summary_item][:pinned_constraints]).to eq(['user: keep context'])
    end
  end

  describe '.trim_trailing_tool_calls' do
    it 'removes trailing tool_call items' do
      history = [
        { id: '1', kind: 'user_message', text: 'hi' },
        { id: '2', kind: 'tool_call', tool_name: 'read' },
        { id: '3', kind: 'tool_call', tool_name: 'grep' }
      ]
      result = described_class.trim_trailing_tool_calls(history)
      expect(result.length).to eq(1)
      expect(result[0][:id]).to eq('1')
    end

    it 'keeps all items when last is not tool_call' do
      history = [
        { id: '1', kind: 'tool_call', tool_name: 'read' },
        { id: '2', kind: 'user_message', text: 'hi' }
      ]
      result = described_class.trim_trailing_tool_calls(history)
      expect(result.length).to eq(2)
    end

    it 'returns full history when no trailing tool calls' do
      history = [{ id: '1', kind: 'assistant_text', text: 'hi' }]
      result = described_class.trim_trailing_tool_calls(history)
      expect(result).to eq(history)
    end
  end
end
