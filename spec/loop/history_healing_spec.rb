# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/history_healing'

RSpec.describe DeepForge::Loop::HistoryHealing do
  describe '.heal' do
    it 'returns items unchanged when all valid' do
      items = [
        { id: '1', kind: 'user_message', text: 'hi' },
        { id: '2', kind: 'assistant_text', text: 'hello' }
      ]
      result = described_class.heal(items)
      expect(result[:changed]).to be(false)
      expect(result[:items].length).to eq(2)
    end

    it 'marks as changed when items are modified' do
      items = [
        { kind: 'user_message', text: 'hi' }
      ]
      result = described_class.heal(items)
      expect(result[:changed]).to be(true)
      expect(result[:items][0][:id]).to include('item_healed')
    end

    it 'removes nil items (non-Hash)' do
      items = [nil, { id: '1', kind: 'user_message', text: 'hi' }]
      result = described_class.heal(items)
      expect(result[:items].length).to eq(1)
    end

    it 'removes items with empty kind' do
      items = [{ id: '1', kind: '', text: 'hi' }]
      result = described_class.heal(items)
      expect(result[:items]).to be_empty
    end

    it 'removes tool_call without call_id' do
      items = [{ id: '1', kind: 'tool_call', tool_name: 'read' }]
      result = described_class.heal(items)
      expect(result[:items]).to be_empty
    end

    it 'removes tool_call without tool_name' do
      items = [{ id: '1', kind: 'tool_call', call_id: 'c1' }]
      result = described_class.heal(items)
      expect(result[:items]).to be_empty
    end

    it 'removes tool_result without call_id' do
      items = [{ id: '1', kind: 'tool_result', tool_name: 'read' }]
      result = described_class.heal(items)
      expect(result[:items]).to be_empty
    end

    it 'keeps valid tool_call' do
      items = [{ id: '1', kind: 'tool_call', call_id: 'c1', tool_name: 'read' }]
      result = described_class.heal(items)
      expect(result[:items].length).to eq(1)
    end

    it 'keeps valid tool_result' do
      items = [{ id: '1', kind: 'tool_result', call_id: 'c1', tool_name: 'read' }]
      result = described_class.heal(items)
      expect(result[:items].length).to eq(1)
    end

    it 'keeps all standard item kinds' do
      kinds = %w[
        assistant_text assistant_reasoning user_message approval
        user_input compaction review error
      ]
      items = kinds.map do |k|
        { id: "1_#{k}", kind: k, text: 'x', message: 'x', summary: 'x', prompt: 'x', title: 'x' }
      end
      result = described_class.heal(items)
      expect(result[:items].length).to eq(kinds.length)
    end

    it 'removes unknown kinds' do
      items = [{ id: '1', kind: 'unknown_type' }]
      result = described_class.heal(items)
      expect(result[:items]).to be_empty
    end

    it 'heals missing id' do
      items = [{ kind: 'user_message', text: 'hi' }]
      result = described_class.heal(items)
      expect(result[:items][0][:id]).to match(/item_healed_0_user_message/)
    end

    it 'heals empty string id' do
      items = [{ id: '  ', kind: 'user_message', text: 'hi' }]
      result = described_class.heal(items)
      expect(result[:items][0][:id]).to include('item_healed')
    end

    it 'accepts string keys' do
      items = [{ 'id' => '1', 'kind' => 'user_message', 'text' => 'hi' }]
      result = described_class.heal(items)
      expect(result[:items].length).to eq(1)
    end
  end

  describe '.normalize_loaded_item' do
    it 'returns nil for non-Hash' do
      expect(described_class.normalize_loaded_item('string', 0)).to be_nil
    end

    it 'returns nil for empty kind' do
      expect(described_class.normalize_loaded_item({ kind: '' }, 0)).to be_nil
    end

    it 'returns nil for missing kind' do
      expect(described_class.normalize_loaded_item({ id: '1' }, 0)).to be_nil
    end

    it 'returns item with healed id' do
      item = { kind: 'user_message', text: 'hi' }
      result = described_class.normalize_loaded_item(item, 5)
      expect(result[:id]).to eq('item_healed_5_user_message')
    end

    it 'preserves existing id' do
      item = { id: 'custom_id', kind: 'user_message', text: 'hi' }
      result = described_class.normalize_loaded_item(item, 0)
      expect(result[:id]).to eq('custom_id')
    end
  end
end
