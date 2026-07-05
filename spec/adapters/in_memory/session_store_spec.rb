# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/in_memory/session_store'

RSpec.describe DeepForge::Adapters::InMemory::SessionStore do
  subject(:store) { described_class.new }

  describe '#append_event' do
    it 'stores events for a thread' do
      store.append_event('t1', seq: 1, kind: 'text')
      store.append_event('t1', seq: 2, kind: 'text')
      expect(store.load_events_since('t1', 0).length).to eq(2)
    end

    it 'deduplicates by seq' do
      store.append_event('t1', seq: 1, kind: 'a')
      store.append_event('t1', seq: 1, kind: 'b')
      expect(store.load_events_since('t1', 0).length).to eq(1)
      expect(store.load_events_since('t1', 0).first[:kind]).to eq('a')
    end

    it 'updates the session projection when present' do
      store.upsert_session(thread_id: 't1', events: [], items: [])
      store.append_event('t1', seq: 1, kind: 'text')
      session = store.load_session('t1')
      expect(session[:events].length).to eq(1)
      expect(session[:updated_at]).to be_a(String)
    end

    it 'does not fail when no session exists' do
      expect { store.append_event('t1', seq: 1) }.not_to raise_error
    end
  end

  describe '#append_item' do
    it 'adds a new item' do
      store.append_item('t1', id: 'i1', text: 'hello')
      expect(store.load_items('t1').length).to eq(1)
    end

    it 'updates an existing item with same id' do
      store.append_item('t1', id: 'i1', text: 'v1')
      store.append_item('t1', id: 'i1', text: 'v2')
      items = store.load_items('t1')
      expect(items.length).to eq(1)
      expect(items.first[:text]).to eq('v2')
    end

    it 'updates the session projection when present' do
      store.upsert_session(thread_id: 't1', events: [], items: [])
      store.append_item('t1', id: 'i1', text: 'hello')
      session = store.load_session('t1')
      expect(session[:items].length).to eq(1)
    end
  end

  describe '#rewrite_items' do
    it 'replaces all items for a thread' do
      store.append_item('t1', id: 'i1', text: 'old')
      store.rewrite_items('t1', [{ id: 'i2', text: 'new' }])
      items = store.load_items('t1')
      expect(items.length).to eq(1)
      expect(items.first[:id]).to eq('i2')
    end

    it 'does not mutate the input array' do
      input = [{ id: 'i1', text: 'hello' }]
      store.rewrite_items('t1', input)
      input.clear
      expect(store.load_items('t1').length).to eq(1)
    end

    it 'updates the session projection when present' do
      store.upsert_session(thread_id: 't1', events: [], items: [{ id: 'i1' }])
      store.rewrite_items('t1', [{ id: 'i2' }])
      expect(store.load_session('t1')[:items].first[:id]).to eq('i2')
    end
  end

  describe '#update_item' do
    it 'patches an existing item and returns it' do
      store.append_item('t1', id: 'i1', text: 'old', extra: true)
      result = store.update_item('t1', 'i1', { text: 'new' })
      expect(result[:text]).to eq('new')
      expect(result[:extra]).to be true
    end

    it 'returns nil when item not found' do
      expect(store.update_item('t1', 'missing', { text: 'x' })).to be_nil
    end

    it 'updates the session projection when present' do
      store.upsert_session(thread_id: 't1', events: [], items: [{ id: 'i1', text: 'old' }])
      store.update_item('t1', 'i1', { text: 'new' })
      expect(store.load_session('t1')[:items].first[:text]).to eq('new')
    end
  end

  describe '#load_events_since' do
    it 'returns events sorted by seq' do
      store.append_event('t1', seq: 5, kind: 'a')
      store.append_event('t1', seq: 2, kind: 'b')
      store.append_event('t1', seq: 8, kind: 'c')
      result = store.load_events_since('t1', 0)
      expect(result.map { |e| e[:seq] }).to eq([2, 5, 8])
    end

    it 'excludes events with seq <= since_seq' do
      store.append_event('t1', seq: 1)
      store.append_event('t1', seq: 2)
      store.append_event('t1', seq: 3)
      expect(store.load_events_since('t1', 2).map { |e| e[:seq] }).to eq([3])
    end

    it 'returns empty for unknown thread' do
      expect(store.load_events_since('unknown', 0)).to eq([])
    end
  end

  describe '#load_items' do
    it 'returns a copy of the items' do
      store.append_item('t1', id: 'i1')
      items = store.load_items('t1')
      items.clear
      expect(store.load_items('t1').length).to eq(1)
    end

    it 'returns empty array for unknown thread' do
      expect(store.load_items('unknown')).to eq([])
    end
  end

  describe '#load_session' do
    it 'returns nil when no session exists' do
      expect(store.load_session('unknown')).to be_nil
    end

    it 'returns the session hash' do
      store.upsert_session(thread_id: 't1', events: [], items: [], title: 'test')
      session = store.load_session('t1')
      expect(session[:title]).to eq('test')
    end
  end

  describe '#upsert_session' do
    it 'stores the session and initializes events/items from it' do
      store.upsert_session(
        thread_id: 't1',
        events: [{ seq: 1 }],
        items: [{ id: 'i1' }],
        title: 'test'
      )
      expect(store.load_events_since('t1', 0).length).to eq(1)
      expect(store.load_items('t1').length).to eq(1)
    end

    it 'does not overwrite existing events/items' do
      store.append_event('t1', seq: 1)
      store.append_item('t1', id: 'i1')
      store.upsert_session(thread_id: 't1', events: [{ seq: 99 }], items: [{ id: 'i99' }])
      expect(store.load_events_since('t1', 0).map { |e| e[:seq] }).to eq([1])
      expect(store.load_items('t1').map { |i| i[:id] }).to eq(['i1'])
    end
  end

  describe '#highest_seq' do
    it 'returns 0 for empty thread' do
      expect(store.highest_seq('t1')).to eq(0)
    end

    it 'returns the max seq' do
      store.append_event('t1', seq: 3)
      store.append_event('t1', seq: 7)
      expect(store.highest_seq('t1')).to eq(7)
    end
  end

  describe '#reset_memory' do
    it 'clears all events, items, and sessions' do
      store.append_event('t1', seq: 1)
      store.append_item('t1', id: 'i1')
      store.upsert_session(thread_id: 't1', events: [], items: [])

      store.reset_memory

      expect(store.load_events_since('t1', 0)).to be_empty
      expect(store.load_items('t1')).to be_empty
      expect(store.load_session('t1')).to be_nil
    end
  end
end
