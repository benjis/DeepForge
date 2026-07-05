# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  def turn_item_double(id:, status: 'running', kind: 'text')
    double(id: id, status: status, kind: kind, to_h: { id: id, status: status, kind: kind })
  end

  def turn_item_struct(id:, status: 'running', kind: 'text')
    OpenStruct.new(id: id, status: status, kind: kind)
  end

  describe '.create_agent_session' do
    it 'creates a session with empty items and events' do
      session = described_class.create_agent_session(thread_id: 't1', turn_id: 'tr1')
      expect(session.thread_id).to eq('t1')
      expect(session.turn_id).to eq('tr1')
      expect(session.items).to eq([])
      expect(session.events).to eq([])
      expect(session.closed).to be(false)
      expect(session.started_at).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it 'uses provided started_at' do
      ts = '2025-06-01T12:00:00Z'
      session = described_class.create_agent_session(thread_id: 't1', turn_id: 'tr1', started_at: ts)
      expect(session.started_at).to eq(ts)
      expect(session.updated_at).to eq(ts)
    end
  end

  describe '.append_session_item' do
    let(:session) { described_class.create_agent_session(thread_id: 't1', turn_id: 'tr1') }

    it 'appends a new item' do
      item = turn_item_struct(id: 'i1')
      result = described_class.append_session_item(session, item)
      expect(result.items.size).to eq(1)
      expect(result.items.first.id).to eq('i1')
    end

    it 'deduplicates by item id' do
      item = turn_item_struct(id: 'i1')
      s1 = described_class.append_session_item(session, item)
      s2 = described_class.append_session_item(s1, item)
      expect(s2.items.size).to eq(1)
    end

    it 'does not mutate original session' do
      item = turn_item_struct(id: 'i1')
      described_class.append_session_item(session, item)
      expect(session.items).to eq([])
    end
  end

  describe '.update_session_item' do
    let(:session) do
      s = described_class.create_agent_session(thread_id: 't1', turn_id: 'tr1')
      described_class.append_session_item(s, turn_item_struct(id: 'i1', status: 'running', kind: 'text'))
    end

    it 'updates matching item' do
      result = described_class.update_session_item(session, 'i1', { status: 'completed' })
      expect(result.items.first.status).to eq('completed')
    end

    it 'returns original session when item not found' do
      result = described_class.update_session_item(session, 'nonexistent', { status: 'done' })
      expect(result).to equal(session)
    end
  end

  describe '.append_session_event' do
    let(:session) { described_class.create_agent_session(thread_id: 't1', turn_id: 'tr1') }

    it 'appends a new event' do
      event = OpenStruct.new(seq: 1)
      result = described_class.append_session_event(session, event)
      expect(result.events.size).to eq(1)
    end

    it 'deduplicates by seq' do
      event = OpenStruct.new(seq: 1)
      s1 = described_class.append_session_event(session, event)
      s2 = described_class.append_session_event(s1, event)
      expect(s2.events.size).to eq(1)
    end
  end

  describe '.close_session' do
    it 'sets closed to true' do
      session = described_class.create_agent_session(thread_id: 't1', turn_id: 'tr1')
      closed = described_class.close_session(session)
      expect(closed.closed).to be(true)
      expect(session.closed).to be(false)
    end
  end
end
