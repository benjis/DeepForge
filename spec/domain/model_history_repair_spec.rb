# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  def tool_call(call_id:, turn_id: 'tr1', id: call_id)
    DeepForge::Contracts::ToolCallTurnItem.new(
      id: id, turn_id: turn_id, thread_id: 't1', role: 'tool',
      status: 'pending', created_at: '2025-01-01T00:00:00Z',
      kind: 'tool_call', tool_name: 'bash', call_id: call_id,
      tool_kind: 'tool_call', arguments: {}, summary: nil
    )
  end

  def tool_result(call_id:, turn_id: 'tr1', id: "r_#{call_id}")
    DeepForge::Contracts::ToolResultTurnItem.new(
      id: id, turn_id: turn_id, thread_id: 't1', role: 'tool',
      status: 'completed', created_at: '2025-01-01T00:00:00Z',
      kind: 'tool_result', tool_name: 'bash', call_id: call_id,
      tool_kind: 'tool_call', output: 'ok', is_error: false
    )
  end

  def user_item(text: 'hi', id: 'u1')
    DeepForge::Contracts::UserTurnItem.new(
      id: id, turn_id: 'tr1', thread_id: 't1', role: 'user',
      status: 'completed', created_at: '2025-01-01T00:00:00Z',
      kind: 'user_message', text: text, display_text: nil, attachment_ids: nil
    )
  end

  def assistant_text(text: 'response', id: 'at1', turn_id: 'tr1')
    DeepForge::Contracts::AssistantTextTurnItem.new(
      id: id, turn_id: turn_id, thread_id: 't1', role: 'assistant',
      status: 'completed', created_at: '2025-01-01T00:00:00Z',
      kind: 'assistant_text', text: text
    )
  end

  def reasoning(text: 'thinking', id: 'ar1')
    DeepForge::Contracts::AssistantReasoningTurnItem.new(
      id: id, turn_id: 'tr1', thread_id: 't1', role: 'assistant',
      status: 'completed', created_at: '2025-01-01T00:00:00Z',
      kind: 'assistant_reasoning', text: text
    )
  end

  describe '.repair_model_history_items' do
    it 'returns items unchanged when all tool calls have matching results' do
      items = [user_item, tool_call(call_id: 'c1'), tool_result(call_id: 'c1')]
      result = described_class.repair_model_history_items(items)
      expect(result).to equal(items)
    end

    it 'removes orphaned tool calls without results' do
      items = [user_item, tool_call(call_id: 'c1'), tool_call(call_id: 'c2'), tool_result(call_id: 'c1')]
      result = described_class.repair_model_history_items(items)
      tool_calls = result.select { |i| i.kind == 'tool_call' }
      tool_call_ids = tool_calls.map(&:call_id)
      expect(tool_call_ids).to eq(['c1'])
    end

    it 'removes orphaned tool results without matching calls' do
      items = [tool_result(call_id: 'c1'), tool_result(call_id: 'c2')]
      result = described_class.repair_model_history_items(items)
      expect(result).to be_empty
    end

    it 'preserves non-tool items' do
      items = [user_item, assistant_text]
      result = described_class.repair_model_history_items(items)
      expect(result.size).to eq(2)
    end

    it 'handles reasoning blocks between call and result as bridge items' do
      items = [tool_call(call_id: 'c1'), reasoning(text: 'thinking'), tool_result(call_id: 'c1')]
      result = described_class.repair_model_history_items(items)
      expect(result.size).to eq(3)
    end

    it 'handles assistant_text as bridge when no result seen yet' do
      items = [tool_call(call_id: 'c1'), assistant_text(text: 'ok'), tool_result(call_id: 'c1')]
      result = described_class.repair_model_history_items(items)
      expect(result.size).to eq(3)
    end

    it 'deduplicates tool calls with same call_id' do
      c1 = tool_call(call_id: 'c1', id: 'tc1')
      c2 = tool_call(call_id: 'c1', id: 'tc2')
      items = [c1, c2, tool_result(call_id: 'c1')]
      result = described_class.repair_model_history_items(items)
      calls = result.select { |i| i.kind == 'tool_call' }
      expect(calls.size).to eq(1)
    end

    it 'returns empty array for empty input' do
      expect(described_class.repair_model_history_items([])).to eq([])
    end
  end

  describe '.tool_result_bridge_item?' do
    let(:options) { { turn_id: 'tr1', saw_result: false } }

    it 'returns true for assistant_reasoning' do
      item = OpenStruct.new(kind: 'assistant_reasoning', turn_id: 'tr1')
      expect(described_class.tool_result_bridge_item?(item, options)).to be true
    end

    it 'returns true for approval' do
      item = OpenStruct.new(kind: 'approval', turn_id: 'tr1')
      expect(described_class.tool_result_bridge_item?(item, options)).to be true
    end

    it 'returns true for error' do
      item = OpenStruct.new(kind: 'error', turn_id: 'tr1')
      expect(described_class.tool_result_bridge_item?(item, options)).to be true
    end

    it 'returns true for assistant_text when no result seen and same turn' do
      item = OpenStruct.new(kind: 'assistant_text', turn_id: 'tr1')
      expect(described_class.tool_result_bridge_item?(item, options)).to be true
    end

    it 'returns false for assistant_text when result already seen' do
      item = OpenStruct.new(kind: 'assistant_text', turn_id: 'tr1')
      expect(described_class.tool_result_bridge_item?(item, options.merge(saw_result: true))).to be false
    end

    it 'returns false for assistant_text on different turn' do
      item = OpenStruct.new(kind: 'assistant_text', turn_id: 'tr2')
      expect(described_class.tool_result_bridge_item?(item, options)).to be false
    end

    it 'returns false for user_message' do
      item = OpenStruct.new(kind: 'user_message', turn_id: 'tr1')
      expect(described_class.tool_result_bridge_item?(item, options)).to be false
    end
  end
end
