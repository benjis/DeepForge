# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/two_arg_event_bus'

RSpec.describe DeepForge::Services::AgentThreadService do
  subject(:threads) do
    described_class.new(thread_store: thread_store, session_store: session_store, events: events, ids: ids,
                        now_iso: now_iso)
  end

  let(:thread_store) { DeepForge::Adapters::Memory::AgentThreadStore.new }
  let(:session_store) { DeepForge::Adapters::InMemory::SessionStore.new }
  let(:inner_event_bus) { DeepForge::Adapters::InMemory::EventBus.new }
  let(:event_bus) { TwoArgEventBus.new(inner_event_bus) }
  let(:ids) { DeepForge::Ports::SequentialIdGenerator.new }
  let(:now_iso) { -> { '2024-01-15T12:00:00Z' } }

  let(:events) do
    DeepForge::Services::RuntimeEventRecorder.new(
      event_bus: event_bus, session_store: session_store,
      allocate_seq: ->(tid) { event_bus.allocate_seq(tid) }, now_iso: now_iso
    )
  end

  describe '#create' do
    it 'creates a thread with generated id' do
      result = threads.create({ workspace: '/tmp', model: 'm1', mode: 'agent' })
      expect(result[:id]).to start_with('thr_')
      expect(result[:workspace]).to eq('/tmp')
      expect(result[:model]).to eq('m1')
      expect(result[:status]).to eq('idle')
    end

    it 'uses provided id and title' do
      result = threads.create({ workspace: '/tmp' }, id: 'custom_id', title: 'My Thread')
      expect(result[:id]).to eq('custom_id')
      expect(result[:title]).to eq('My Thread')
    end

    it 'defaults title to "New chat"' do
      expect(threads.create({ workspace: '/' })[:title]).to eq('New chat')
    end

    it 'records thread_created event' do
      threads.create({ workspace: '/tmp' }, id: 't1')
      expect(session_store.load_events_since('t1', 0).find { |e| e[:kind] == 'thread_created' }).not_to be_nil
    end
  end

  describe '#get' do
    it 'returns thread by id' do
      threads.create({ workspace: '/tmp' }, id: 't1', title: 'Test')
      expect(threads.get('t1')[:title]).to eq('Test')
    end

    it 'returns nil for nonexistent thread' do
      expect(threads.get('nonexistent')).to be_nil
    end
  end

  describe '#update' do
    it 'updates thread fields' do
      threads.create({ workspace: '/tmp' }, id: 't1', title: 'Old')
      expect(threads.update('t1', { title: 'New' })[:title]).to eq('New')
    end

    it 'raises when thread not found' do
      expect { threads.update('nonexistent', { title: 'x' }) }.to raise_error(RuntimeError, /thread not found/)
    end
  end

  describe '#delete' do
    it 'deletes a thread' do
      threads.create({ workspace: '/tmp' }, id: 't1')
      expect(threads.delete('t1')).to be true
      expect(threads.get('t1')).to be_nil
    end

    it 'returns false for nonexistent' do
      expect(threads.delete('nonexistent')).to be false
    end
  end

  describe '#list' do
    it 'returns non-archived threads by default' do
      threads.create({ workspace: '/tmp' }, id: 't1', title: 'Active')
      threads.create({ workspace: '/tmp' }, id: 't2', title: 'Archived')
      threads.update('t2', { status: 'archived' })
      ids = threads.list.map { |t| t[:id] }
      expect(ids).to include('t1')
      expect(ids).not_to include('t2')
    end

    it 'searches by query' do
      threads.create({ workspace: '/tmp' }, id: 't1', title: 'My Project')
      threads.create({ workspace: '/tmp' }, id: 't2', title: 'Other')
      expect(threads.list(search: 'project').map { |t| t[:id] }).to include('t1')
    end

    it 'applies limit' do
      5.times { |i| threads.create({ workspace: '/tmp' }, id: "t#{i}") }
      expect(threads.list(limit: 2).length).to eq(2)
    end
  end

  describe '#get_goal / #set_goal / #clear_goal' do
    before { threads.create({ workspace: '/tmp' }, id: 't1') }

    it 'returns nil when no goal' do
      expect(threads.get_goal('t1')).to be_nil
    end

    it 'creates and returns a goal in camelCase' do
      goal = threads.set_goal('t1', { objective: 'Build feature', status: 'active' })
      expect(goal[:objective]).to eq('Build feature')
      expect(goal[:tokensUsed]).to eq(0)
    end

    it 'updates an existing goal' do
      threads.set_goal('t1', { objective: 'First' })
      expect(threads.set_goal('t1', { objective: 'Second' })[:objective]).to eq('Second')
    end

    it 'raises when no existing goal and no objective' do
      expect { threads.set_goal('t1', { status: 'active' }) }.to raise_error(RuntimeError, /no goal exists/)
    end

    it 'clears an existing goal' do
      threads.set_goal('t1', { objective: 'Build' })
      expect(threads.clear_goal('t1')).to be true
      expect(threads.get_goal('t1')).to be_nil
    end

    it 'returns false when no goal' do
      expect(threads.clear_goal('t1')).to be false
    end
  end

  describe '#get_todos / #set_todos / #clear_todos' do
    before { threads.create({ workspace: '/tmp' }, id: 't1') }

    it 'returns nil when no todos' do
      expect(threads.get_todos('t1')).to be_nil
    end

    it 'sets todos with items' do
      result = threads.set_todos('t1',
                                 { todos: [{ content: 'A', status: 'pending' },
                                           { content: 'B', status: 'completed' }] })
      expect(result[:items].length).to eq(2)
    end

    it 'raises for duplicate in_progress' do
      expect do
        threads.set_todos('t1',
                          { todos: [{ content: 'A', status: 'in_progress' }, { content: 'B', status: 'in_progress' }] })
      end.to raise_error(RuntimeError, /at most one todo can be in_progress/)
    end

    it 'clears todos' do
      threads.set_todos('t1', { todos: [{ content: 'A', status: 'pending' }] })
      expect(threads.clear_todos('t1')).to be true
      expect(threads.get_todos('t1')).to be_nil
    end
  end

  describe '#to_summary' do
    it 'returns summary without turns' do
      threads.create({ workspace: '/tmp', model: 'm1' }, id: 't1', title: 'Test')
      summary = threads.to_summary(threads.get('t1'))
      expect(summary[:id]).to eq('t1')
      expect(summary).not_to have_key(:turns)
    end
  end
end
