# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  def make_turn_item(id:, status: 'running', kind: 'text')
    OpenStruct.new(id: id, status: status, kind: kind, to_h: { id: id, status: status, kind: kind },
                   class: OpenStruct)
  end

  describe '.create_turn_record' do
    it 'creates a turn with queued status by default' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1')
      expect(turn.id).to eq('tr1')
      expect(turn.thread_id).to eq('t1')
      expect(turn.status).to eq('queued')
      expect(turn.steering).to eq([])
      expect(turn.items).to eq([])
      expect(turn.attachment_ids).to eq([])
    end

    it 'uses provided status' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1', status: 'running')
      expect(turn.status).to eq('running')
    end

    it 'strips model name' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1', model: '  deepseek-chat  ')
      expect(turn.model).to eq('deepseek-chat')
    end

    it 'normalizes reasoning_effort auto to nil' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 'tr1', reasoning_effort: 'auto')
      expect(turn.reasoning_effort).to be_nil
    end

    it 'normalizes nil reasoning_effort to nil' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 'tr1', reasoning_effort: nil)
      expect(turn.reasoning_effort).to be_nil
    end

    it 'preserves specific reasoning_effort values' do
      %w[off low medium high max].each do |level|
        turn = described_class.create_turn_record(id: "tr_#{level}", thread_id: 't1', reasoning_effort: level)
        expect(turn.reasoning_effort).to eq(level)
      end
    end

    it 'dups attachment_ids to avoid shared mutation' do
      ids = ['a1']
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1', attachment_ids: ids)
      ids << 'a2'
      expect(turn.attachment_ids).to eq(['a1'])
    end
  end

  describe '.append_turn_item' do
    let(:turn) { described_class.create_turn_record(id: 'tr1', thread_id: 't1') }

    it 'appends a new item' do
      item = OpenStruct.new(id: 'i1')
      result = described_class.append_turn_item(turn, item)
      expect(result.items.size).to eq(1)
    end

    it 'replaces item with same id' do
      item1 = OpenStruct.new(id: 'i1', status: 'running')
      item2 = OpenStruct.new(id: 'i1', status: 'completed')
      s1 = described_class.append_turn_item(turn, item1)
      s2 = described_class.append_turn_item(s1, item2)
      expect(s2.items.size).to eq(1)
      expect(s2.items.first.status).to eq('completed')
    end

    it 'does not mutate original turn' do
      item = OpenStruct.new(id: 'i1')
      described_class.append_turn_item(turn, item)
      expect(turn.items).to eq([])
    end
  end

  describe '.replace_turn_item' do
    it 'merges patch into existing item' do
      t = described_class.create_turn_record(id: 'tr1', thread_id: 't1')
      item = DeepForge::Contracts::AssistantTextTurnItem.new(
        id: 'i1', turn_id: 'tr1', thread_id: 't1', role: 'assistant',
        status: 'running', kind: 'assistant_text', text: 'hello'
      )
      t2 = described_class.append_turn_item(t, item)
      result = described_class.replace_turn_item(t2, 'i1', { status: 'completed' })
      expect(result.items.first.status).to eq('completed')
    end

    it 'does nothing for non-existent item id' do
      t = described_class.create_turn_record(id: 'tr1', thread_id: 't1')
      item = DeepForge::Contracts::AssistantTextTurnItem.new(
        id: 'i1', turn_id: 'tr1', thread_id: 't1', role: 'assistant',
        status: 'running', kind: 'assistant_text', text: 'hello'
      )
      t2 = described_class.append_turn_item(t, item)
      result = described_class.replace_turn_item(t2, 'nonexistent', { status: 'done' })
      expect(result.items.first.status).to eq('running')
    end
  end

  describe '.start_turn' do
    it 'sets status to running and adds started_at' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1')
      started = described_class.start_turn(turn)
      expect(started.status).to eq('running')
      expect(started.started_at).to match(/\d{4}/)
    end

    it 'uses provided started_at' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1')
      ts = '2025-06-01T12:00:00Z'
      started = described_class.start_turn(turn, started_at: ts)
      expect(started.started_at).to eq(ts)
    end
  end

  describe '.finish_turn' do
    it 'sets status and finished_at, clears steering' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1')
      finished = described_class.finish_turn(turn, DeepForge::Contracts::TurnStatus::COMPLETED)
      expect(finished.status).to eq('completed')
      expect(finished.finished_at).to match(/\d{4}/)
      expect(finished.steering).to eq([])
    end

    it 'uses provided finished_at' do
      turn = described_class.create_turn_record(id: 'tr1', thread_id: 't1')
      ts = '2025-06-01T12:00:00Z'
      finished = described_class.finish_turn(turn, 'failed', finished_at: ts)
      expect(finished.finished_at).to eq(ts)
      expect(finished.status).to eq('failed')
    end
  end
end
