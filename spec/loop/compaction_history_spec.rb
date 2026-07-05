# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/compaction_history'

RSpec.describe DeepForge::Loop::CompactionHistory do
  describe '.effective_history_after_latest_compaction' do
    it 'returns all items when no compaction marker' do
      items = [
        { id: '1', kind: 'user_message', text: 'hi' },
        { id: '2', kind: 'assistant_text', text: 'hello' }
      ]
      result = described_class.effective_history_after_latest_compaction(items)
      expect(result).to eq(items)
    end

    it 'returns items after the latest compaction with replaced_tokens > 0' do
      items = [
        { id: '1', kind: 'user_message', text: 'hi' },
        { id: '2', kind: 'compaction', replaced_tokens: 0, summary: 'noop' },
        { id: '3', kind: 'user_message', text: 'after' },
        { id: '4', kind: 'compaction', replaced_tokens: 500, summary: 'real compaction' },
        { id: '5', kind: 'assistant_text', text: 'response' }
      ]
      result = described_class.effective_history_after_latest_compaction(items)
      expect(result.map { |i| i[:id] }).to eq(%w[4 5])
    end

    it 'does not treat replaced_tokens 0 as compaction point' do
      items = [
        { id: '1', kind: 'compaction', replaced_tokens: 0 },
        { id: '2', kind: 'user_message', text: 'hi' }
      ]
      result = described_class.effective_history_after_latest_compaction(items)
      expect(result.map { |i| i[:id] }).to eq(%w[1 2])
    end

    it 'does not mutate the original array' do
      items = [{ id: '1', kind: 'user_message', text: 'hi' }]
      result = described_class.effective_history_after_latest_compaction(items)
      expect(result).not_to equal(items)
    end
  end

  describe '.place_compactions_at_turn_end' do
    it 'returns items unchanged when no trailing compactions' do
      items = [
        { id: '1', kind: 'user_message', text: 'hi' },
        { id: '2', kind: 'compaction', replaced_tokens: 0 }
      ]
      result = described_class.place_compactions_at_turn_end(items)
      expect(result.map { |i| i[:id] }).to eq(%w[1 2])
    end

    it 'moves compaction markers to the end' do
      items = [
        { id: '1', kind: 'compaction', replaced_tokens: 100, summary: 'c1' },
        { id: '2', kind: 'user_message', text: 'hi' },
        { id: '3', kind: 'compaction', replaced_tokens: 200, summary: 'c2' },
        { id: '4', kind: 'assistant_text', text: 'bye' }
      ]
      result = described_class.place_compactions_at_turn_end(items)
      expect(result.map { |i| i[:id] }).to eq(%w[2 4 1 3])
    end

    it 'does not mutate the original array' do
      items = [
        { id: '1', kind: 'compaction', replaced_tokens: 100 },
        { id: '2', kind: 'user_message', text: 'hi' }
      ]
      result = described_class.place_compactions_at_turn_end(items)
      expect(result).not_to equal(items)
    end
  end

  describe '.insert_compaction_into_visible_history' do
    it 'appends summary when not found in compacted items' do
      visible = [{ id: 'v1' }, { id: 'v2' }]
      compacted = [{ id: 'v1' }, { id: 'v2' }, { id: 'summary' }]
      summary = { id: 'summary' }
      result = described_class.insert_compaction_into_visible_history(
        visible_items: visible, compacted_items: compacted, summary_item: summary
      )
      ids = result.map { |i| i[:id] }
      expect(ids).to eq(%w[v1 v2 summary])
    end

    it 'inserts summary before tail items' do
      visible = [{ id: 'v1' }, { id: 'v2' }, { id: 'v3' }]
      compacted = [{ id: 'v1' }, { id: 'summary' }, { id: 'v2' }, { id: 'v3' }]
      summary = { id: 'summary' }
      result = described_class.insert_compaction_into_visible_history(
        visible_items: visible, compacted_items: compacted, summary_item: summary
      )
      ids = result.map { |i| i[:id] }
      expect(ids).to eq(%w[v1 summary v2 v3])
    end

    it 'replaces existing summary in visible' do
      visible = [{ id: 'v1' }, { id: 'old_summary' }, { id: 'v2' }]
      compacted = [{ id: 'v1' }, { id: 'new_summary' }, { id: 'v2' }]
      summary = { id: 'new_summary' }
      result = described_class.insert_compaction_into_visible_history(
        visible_items: visible, compacted_items: compacted, summary_item: summary
      )
      expect(result.map { |i| i[:id] }).to include('new_summary')
    end
  end
end
