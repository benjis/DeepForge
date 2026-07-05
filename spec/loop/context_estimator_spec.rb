# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/compaction/estimator'

RSpec.describe DeepForge::Loop::ContextEstimator do
  subject(:estimator) { described_class.new(chars_per_token) }

  let(:chars_per_token) { 4 }

  describe '#initialize' do
    it 'accepts custom chars_per_token' do
      e = described_class.new(2)
      expect(e).to be_a(described_class)
    end

    it 'defaults to 4 chars per token' do
      e = described_class.new
      item = { kind: 'user_message', text: 'a' * 40 }
      expect(e.estimate_item(item)).to eq(10)
    end
  end

  describe '#estimate_item' do
    it 'estimates user_message tokens' do
      item = { kind: 'user_message', text: 'a' * 20 }
      expect(estimator.estimate_item(item)).to eq(5)
    end

    it 'estimates assistant_text tokens' do
      item = { kind: 'assistant_text', text: 'b' * 16 }
      expect(estimator.estimate_item(item)).to eq(4)
    end

    it 'estimates assistant_reasoning tokens' do
      item = { kind: 'assistant_reasoning', text: 'c' * 8 }
      expect(estimator.estimate_item(item)).to eq(2)
    end

    it 'estimates tool_call tokens' do
      item = { kind: 'tool_call', tool_name: 'read', arguments: { path: '/foo' } }
      tokens = estimator.estimate_item(item)
      expect(tokens).to be >= 1
    end

    it 'estimates tool_result string output' do
      item = { kind: 'tool_result', output: 'd' * 40 }
      expect(estimator.estimate_item(item)).to eq(10)
    end

    it 'estimates tool_result hash output' do
      item = { kind: 'tool_result', output: { key: 'value' } }
      expect(estimator.estimate_item(item)).to be >= 1
    end

    it 'estimates approval tokens' do
      item = { kind: 'approval', tool_name: 'bash', summary: 'run command' }
      expect(estimator.estimate_item(item)).to be >= 1
    end

    it 'estimates user_input tokens' do
      item = { kind: 'user_input', prompt: 'e' * 12 }
      expect(estimator.estimate_item(item)).to eq(3)
    end

    it 'estimates compaction tokens' do
      item = { kind: 'compaction', summary: 'f' * 32 }
      expect(estimator.estimate_item(item)).to eq(8)
    end

    it 'estimates review tokens' do
      item = { kind: 'review', title: 'Review', review_text: 'g' * 20 }
      expect(estimator.estimate_item(item)).to be >= 1
    end

    it 'estimates error tokens' do
      item = { kind: 'error', message: 'h' * 24 }
      expect(estimator.estimate_item(item)).to eq(6)
    end

    it 'returns at least 1 token' do
      item = { kind: 'unknown_kind' }
      expect(estimator.estimate_item(item)).to eq(1)
    end
  end

  describe '#estimate_items' do
    it 'returns 0 for empty array' do
      expect(estimator.estimate_items([])).to eq(0)
    end

    it 'sums tokens across items' do
      items = [
        { kind: 'user_message', text: 'a' * 20 },
        { kind: 'assistant_text', text: 'b' * 20 }
      ]
      expect(estimator.estimate_items(items)).to eq(10)
    end
  end
end
