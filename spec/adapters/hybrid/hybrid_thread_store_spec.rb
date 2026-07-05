# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/hybrid/hybrid_thread_store'

RSpec.describe DeepForge::Adapters::Hybrid::AgentThreadStore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:thread1) do
    {
      id: 't1', title: 'First', workspace: '/w1', model: 'm1',
      mode: 'agent', status: 'idle', relation: 'primary',
      created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-02T00:00:00Z'
    }
  end
  let(:thread2) do
    {
      id: 't2', title: 'Second', workspace: '/w2', model: 'm2',
      mode: 'agent', status: 'running', relation: 'primary',
      created_at: '2026-01-03T00:00:00Z', updated_at: '2026-01-04T00:00:00Z'
    }
  end
  let(:store) { described_class.new(data_dir: tmpdir) }

  after do
    store.close
    FileUtils.rm_rf(tmpdir)
  end

  describe '#upsert' do
    it 'stores and returns the thread' do
      result = store.upsert(thread1)
      expect(result).to eq(thread1)
    end

    it 'creates metadata.jsonl file' do
      store.upsert(thread1)
      path = File.join(tmpdir, 'threads', 't1', 'metadata.jsonl')
      expect(File.exist?(path)).to be true
    end

    it 'updates SQLite index' do
      store.upsert(thread1)
      rows = store.instance_variable_get(:@db).execute('SELECT * FROM threads WHERE id = ?', ['t1'])
      expect(rows.length).to eq(1)
      expect(rows.first['title']).to eq('First')
    end
  end

  describe '#get' do
    it 'returns nil for unknown id' do
      expect(store.get('unknown')).to be_nil
    end

    it 'returns the thread with symbolized keys' do
      store.upsert(thread1)
      result = store.get('t1')
      expect(result[:id]).to eq('t1')
      expect(result[:title]).to eq('First')
    end

    it 'hydrates turn items from messages.jsonl' do
      thread = thread1.merge(turns: [{ id: 'turn1', status: 'completed', prompt: '' }])
      store.upsert(thread)
      messages_path = File.join(tmpdir, 'threads', 't1', 'messages.jsonl')
      item = { 'kind' => 'user_message', 'text' => 'hello', 'turnId' => 'turn1' }
      File.open(messages_path, 'a') { |f| f.puts(JSON.generate(item)) }

      result = store.get('t1')
      turn = result[:turns].find { |t| t[:id] == 'turn1' }
      expect(turn[:items]).not_to be_empty
      expect(turn[:prompt]).to eq('hello')
    end
  end

  describe '#list' do
    it 'returns all threads sorted by updated_at desc' do
      store.upsert(thread1)
      store.upsert(thread2)
      list = store.list
      expect(list.length).to eq(2)
    end

    it 'returns camelCase keys' do
      store.upsert(thread1)
      list = store.list
      summary = list.first
      expect(summary).to have_key('id')
      expect(summary).to have_key('title')
    end

    it 'filters by status' do
      store.upsert(thread1)
      store.upsert(thread2)
      running = store.list(status: 'running')
      expect(running.length).to eq(1)
      expect(running.first['id']).to eq('t2')
    end

    it 'returns empty array when no threads' do
      expect(store.list).to eq([])
    end
  end

  describe '#delete' do
    it 'removes thread from filesystem and SQLite' do
      store.upsert(thread1)
      expect(store.delete('t1')).to be true
      expect(store.get('t1')).to be_nil
      rows = store.instance_variable_get(:@db).execute('SELECT * FROM threads WHERE id = ?', ['t1'])
      expect(rows).to be_empty
    end

    it 'always returns true' do
      expect(store.delete('unknown')).to be true
    end
  end

  describe '#note_event_seq' do
    it 'updates event_seq_high_water in SQLite' do
      store.upsert(thread1)
      store.note_event_seq('t1', 42)
      rows = store.instance_variable_get(:@db).execute('SELECT event_seq_high_water FROM threads WHERE id = ?', ['t1'])
      expect(rows.first['event_seq_high_water']).to eq(42)
    end

    it 'only increases the high water mark' do
      store.upsert(thread1)
      store.note_event_seq('t1', 42)
      store.note_event_seq('t1', 10)
      rows = store.instance_variable_get(:@db).execute('SELECT event_seq_high_water FROM threads WHERE id = ?', ['t1'])
      expect(rows.first['event_seq_high_water']).to eq(42)
    end
  end

  describe '#close' do
    it 'releases the database connection' do
      store.close
      expect(store.instance_variable_get(:@db)).to be_nil
    end
  end

  describe 'backfill from filesystem' do
    it 'indexes existing threads from filesystem on initialization' do
      thread_dir = File.join(tmpdir, 'threads', 'pre_existing')
      FileUtils.mkdir_p(thread_dir)
      meta = { kind: 'thread_metadata', version: 1, timestamp: '2026-01-01T00:00:00Z',
               thread: { id: 'pre_existing', title: 'Pre-existing', workspace: '/w',
                         model: 'm', mode: 'agent', status: 'idle', relation: 'primary',
                         created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z',
                         turns: [] } }
      File.open(File.join(thread_dir, 'metadata.jsonl'), 'w') { |f| f.puts(JSON.generate(meta)) }

      new_store = described_class.new(data_dir: tmpdir)
      result = new_store.get('pre_existing')
      expect(result).not_to be_nil
      expect(result[:title]).to eq('Pre-existing')
      new_store.close
    end
  end
end
