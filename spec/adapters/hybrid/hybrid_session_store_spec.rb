# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/hybrid/hybrid_session_store'

RSpec.describe DeepForge::Adapters::Hybrid::HybridSessionStore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:store) { described_class.new(data_dir: tmpdir, index: index) }
  let(:index) { DeepForge::Adapters::Hybrid::AgentThreadStore.new(data_dir: tmpdir) }

  before do
    # DeepForge::Adapters::FileStore was renamed from File to avoid shadowing ::File
    # HybridSessionStore delegates to File::FileSessionStore, so re-add it here.
    load File.expand_path('../../../lib/deepforge/adapters/file/atomic_write.rb', __dir__)
    load File.expand_path('../../../lib/deepforge/adapters/file/agent_thread_store.rb', __dir__)
    load File.expand_path('../../../lib/deepforge/adapters/file/file_session_store.rb', __dir__)
  end

  after do
    index.close
    FileUtils.rm_rf(tmpdir)
  end

  describe '#append_event' do
    it 'writes event to file and loads it back' do
      store.append_event('t1', { seq: 5, kind: 'text' })
      events = store.load_events_since('t1', 0)
      expect(events.length).to eq(1)
      expect(events.first[:seq]).to eq(5)
    end
  end

  describe '#append_item' do
    it 'delegates to file store' do
      store.append_item('t1', { id: 'i1', text: 'hello' })
      items = store.load_items('t1')
      expect(items.length).to eq(1)
      expect(items.first[:id]).to eq('i1')
    end
  end

  describe '#rewrite_items' do
    it 'delegates to file store' do
      store.append_item('t1', { id: 'i1', text: 'old' })
      store.rewrite_items('t1', [{ id: 'i2', text: 'new' }])
      items = store.load_items('t1')
      expect(items.length).to eq(1)
      expect(items.first[:id]).to eq('i2')
    end
  end

  describe '#update_item' do
    it 'delegates to file store' do
      store.append_item('t1', { id: 'i1', text: 'old' })
      result = store.update_item('t1', 'i1', { text: 'new' })
      expect(result[:text]).to eq('new')
    end

    it 'returns nil when item not found' do
      expect(store.update_item('t1', 'missing', { text: 'x' })).to be_nil
    end
  end

  describe '#load_events_since' do
    it 'filters by since_seq' do
      store.append_event('t1', { seq: 1 })
      store.append_event('t1', { seq: 5 })
      events = store.load_events_since('t1', 1)
      expect(events.map { |e| e[:seq] }).to eq([5])
    end
  end

  describe '#load_items' do
    it 'returns items' do
      store.append_item('t1', { id: 'i1' })
      expect(store.load_items('t1').length).to eq(1)
    end
  end

  describe '#load_session' do
    it 'returns nil when no session exists' do
      expect(store.load_session('unknown')).to be_nil
    end

    it 'returns session after upsert' do
      store.upsert_session({ thread_id: 't1', events: [], items: [], title: 'test' })
      expect(store.load_session('t1')[:title]).to eq('test')
    end
  end

  describe '#upsert_session' do
    it 'writes session file' do
      store.upsert_session({ thread_id: 't1', events: [], items: [] })
      path = File.join(tmpdir, 'threads', 't1', 'session.json')
      expect(File.exist?(path)).to be true
    end
  end

  describe '#highest_seq' do
    it 'returns max seq' do
      store.append_event('t1', { seq: 3 })
      expect(store.highest_seq('t1')).to eq(3)
    end
  end

  describe '#reset_memory' do
    it 'does not raise' do
      store.reset_memory
    end
  end
end
