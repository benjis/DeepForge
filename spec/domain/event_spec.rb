# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  describe '.compare_event_seq' do
    it 'returns negative when a.seq < b.seq' do
      a = OpenStruct.new(seq: 1)
      b = OpenStruct.new(seq: 5)
      expect(described_class.compare_event_seq(a, b)).to eq(-4)
    end

    it 'returns positive when a.seq > b.seq' do
      a = OpenStruct.new(seq: 10)
      b = OpenStruct.new(seq: 3)
      expect(described_class.compare_event_seq(a, b)).to eq(7)
    end

    it 'returns zero when seqs are equal' do
      a = OpenStruct.new(seq: 42)
      b = OpenStruct.new(seq: 42)
      expect(described_class.compare_event_seq(a, b)).to eq(0)
    end
  end

  describe '.group_events_by_kind' do
    it 'groups events by their kind field' do
      events = [
        OpenStruct.new(kind: 'tool_call_started'),
        OpenStruct.new(kind: 'assistant_text_delta'),
        OpenStruct.new(kind: 'tool_call_started'),
        OpenStruct.new(kind: 'usage')
      ]
      result = described_class.group_events_by_kind(events)
      expect(result.keys).to contain_exactly('tool_call_started', 'assistant_text_delta', 'usage')
      expect(result['tool_call_started'].size).to eq(2)
      expect(result['assistant_text_delta'].size).to eq(1)
    end

    it 'returns empty hash for empty array' do
      expect(described_class.group_events_by_kind([])).to eq({})
    end

    it 'preserves insertion order within groups' do
      e1 = OpenStruct.new(kind: 'a', seq: 1)
      e2 = OpenStruct.new(kind: 'a', seq: 2)
      result = described_class.group_events_by_kind([e1, e2])
      expect(result['a']).to eq([e1, e2])
    end
  end
end
