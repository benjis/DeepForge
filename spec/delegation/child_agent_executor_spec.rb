# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Delegation do
  describe '.child_thread_title' do
    it 'generates title with child_id when no label' do
      title = described_class.child_thread_title('child_1')
      expect(title).to eq('Child agent: child_1')
    end

    it 'generates title with label' do
      title = described_class.child_thread_title('child_1', label: 'search task')
      expect(title).to eq('Child agent: search task')
    end

    it 'strips whitespace from label' do
      title = described_class.child_thread_title('child_1', label: '  task  ')
      expect(title).to eq('Child agent: task')
    end
  end

  describe '.stringify_summary' do
    it 'returns stripped string value' do
      expect(described_class.stringify_summary('  hello  ')).to eq('hello')
    end

    it 'returns empty string for nil' do
      expect(described_class.stringify_summary(nil)).to eq('')
    end

    it 'converts non-string value to JSON' do
      result = described_class.stringify_summary({ key: 'value' })
      expect(JSON.parse(result)).to eq({ 'key' => 'value' })
    end
  end

  describe '.summarize_child_turn' do
    it 'returns assistant text when available' do
      items = [
        { turn_id: 'turn1', kind: 'assistant_text', text: 'Hello world' },
        { turn_id: 'turn1', kind: 'tool_result', output: 'result' }
      ]
      result = described_class.summarize_child_turn(items, 'turn1', 'completed')
      expect(result).to eq('Hello world')
    end

    it 'returns error messages when no assistant text' do
      items = [
        { turn_id: 'turn1', kind: 'error', message: 'Something failed' }
      ]
      result = described_class.summarize_child_turn(items, 'turn1', 'failed')
      expect(result).to eq('Something failed')
    end

    it 'returns tool result output as fallback' do
      items = [
        { turn_id: 'turn1', kind: 'tool_result', output: 'Tool output' }
      ]
      result = described_class.summarize_child_turn(items, 'turn1', 'completed')
      expect(result).to eq('Tool output')
    end

    it 'returns default message when no items' do
      result = described_class.summarize_child_turn([], 'turn1', 'completed')
      expect(result).to eq('Child agent completed without a text response.')
    end

    it 'returns status-specific message for non-completed' do
      result = described_class.summarize_child_turn([], 'turn1', 'failed')
      expect(result).to eq('Child agent failed.')
    end

    it 'filters items by turn_id' do
      items = [
        { turn_id: 'other', kind: 'assistant_text', text: 'Other turn' },
        { turn_id: 'turn1', kind: 'assistant_text', text: 'My turn' }
      ]
      result = described_class.summarize_child_turn(items, 'turn1', 'completed')
      expect(result).to eq('My turn')
    end
  end
end
