# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/two_arg_event_bus'

RSpec.describe DeepForge::Services::DialogueTurnService do
  subject(:turns) do
    described_class.new(
      thread_store: thread_store, session_store: session_store, events: events,
      inflight: inflight, steering: steering, compactor: compactor, ids: ids, now_iso: now_iso
    )
  end

  let(:thread_store) { DeepForge::Adapters::Memory::AgentThreadStore.new }
  let(:thread_id) { 'thr_test1' }
  let(:session_store) { DeepForge::Adapters::InMemory::SessionStore.new }
  let(:inner_event_bus) { DeepForge::Adapters::InMemory::EventBus.new }
  let(:event_bus) { TwoArgEventBus.new(inner_event_bus) }
  let(:inflight) { DeepForge::Loop::InflightTracker.new }
  let(:steering) { DeepForge::Loop::SteeringQueue.new }
  let(:compactor) { DeepForge::Loop::ContextCompactor.new }
  let(:ids) { DeepForge::Ports::SequentialIdGenerator.new }
  let(:now_iso) { -> { '2024-01-15T12:00:00Z' } }

  let(:events) do
    DeepForge::Services::RuntimeEventRecorder.new(
      event_bus: event_bus, session_store: session_store,
      allocate_seq: ->(tid) { event_bus.allocate_seq(tid) }, now_iso: now_iso
    )
  end

  before do
    thread_store.upsert({
                          id: thread_id, title: 'Test', workspace: '/tmp', model: 'test-model',
                          mode: 'agent', status: 'idle', turns: [],
                          created_at: now_iso.call, updated_at: now_iso.call
                        })
  end

  describe '#start_turn' do
    it 'creates a new turn with running status' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      expect(result[:thread_id]).to eq(thread_id)
      expect(result[:turn_id]).to start_with('turn_')
      expect(result[:user_message_item_id]).to start_with('item_')
    end

    it 'updates thread status to running' do
      turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      thread = thread_store.get(thread_id)
      expect(thread[:status]).to eq('running')
      expect(thread[:turns].first[:status]).to eq('running')
    end

    it 'records turn_started event' do
      turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      events = session_store.load_events_since(thread_id, 0)
      expect(events.find { |e| e[:kind] == 'turn_started' }).not_to be_nil
    end

    it 'creates user message item in session store' do
      turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      user_items = session_store.load_items(thread_id).select { |i| i[:kind] == 'user_message' }
      expect(user_items.length).to eq(1)
      expect(user_items.first[:text]).to eq('hello')
    end

    it 'registers inflight tracker entry' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      expect(inflight.has?(result[:turn_id])).to be true
    end

    it 'raises when thread not found' do
      expect do
        turns.start_turn(thread_id: 'nonexistent',
                         request: { prompt: 'hello' })
      end.to raise_error(RuntimeError, /thread not found/)
    end
  end

  describe '#steer_turn' do
    it 'enqueues steering text' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      turns.steer_turn(thread_id: thread_id, turn_id: result[:turn_id], text: 'go left')
      expect(steering.peek).to include('go left')
    end
  end

  describe '#interrupt_turn' do
    it 'aborts the turn and clears steering' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      turns.steer_turn(thread_id: thread_id, turn_id: result[:turn_id], text: 'go left')
      turns.interrupt_turn(thread_id: thread_id, turn_id: result[:turn_id])

      thread = thread_store.get(thread_id)
      expect(thread[:turns].first[:status]).to eq('aborted')
      expect(thread[:status]).to eq('idle')
      expect(inflight.has?(result[:turn_id])).to be false
      expect(steering.peek).to be_empty
    end

    it 'returns { status: aborted }' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      expect(turns.interrupt_turn(thread_id: thread_id, turn_id: result[:turn_id])).to eq({ status: 'aborted' })
    end
  end

  describe '#finish_turn' do
    it 'marks turn as completed and thread as idle' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      turns.finish_turn(thread_id: thread_id, turn_id: result[:turn_id], status: 'completed')
      thread = thread_store.get(thread_id)
      expect(thread[:turns].first[:status]).to eq('completed')
      expect(thread[:status]).to eq('idle')
    end

    it 'records turn_completed event' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      turns.finish_turn(thread_id: thread_id, turn_id: result[:turn_id], status: 'completed')
      expect(session_store.load_events_since(thread_id, 0).find { |e| e[:kind] == 'turn_completed' }).not_to be_nil
    end

    it 'appends error item when error provided' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      turns.finish_turn(thread_id: thread_id, turn_id: result[:turn_id], status: 'failed', error: 'boom')
      error_items = session_store.load_items(thread_id).select { |i| i[:kind] == 'error' }
      expect(error_items.length).to eq(1)
      expect(error_items.first[:message]).to eq('boom')
    end

    it 'clears inflight tracker and steering' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      turns.steer_turn(thread_id: thread_id, turn_id: result[:turn_id], text: 'go left')
      turns.finish_turn(thread_id: thread_id, turn_id: result[:turn_id], status: 'completed')
      expect(inflight.has?(result[:turn_id])).to be false
      expect(steering.peek).to be_empty
    end
  end

  describe '#get_abort_controller' do
    it 'returns nil for unknown turn_id' do
      expect(turns.get_abort_controller('unknown')).to be_nil
    end

    it 'returns an AbortSignal after start_turn' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      signal = turns.get_abort_controller(result[:turn_id])
      expect(signal).to be_a(described_class::AbortSignal)
      expect(signal.rejected?).to be false
    end
  end

  describe '#AbortSignal' do
    it 'is not rejected by default' do
      expect(described_class::AbortSignal.new.rejected?).to be false
    end

    it 'becomes rejected after reject' do
      signal = described_class::AbortSignal.new
      signal.reject('interrupted')
      expect(signal.rejected?).to be true
      expect(signal.rejected_reason).to eq('interrupted')
    end
  end

  describe '#get_turn' do
    it 'returns the turn record' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      turn = turns.get_turn(thread_id, result[:turn_id])
      expect(turn).not_to be_nil
      expect(turn[:id]).to eq(result[:turn_id])
    end

    it 'returns nil for nonexistent turn' do
      expect(turns.get_turn(thread_id, 'nonexistent')).to be_nil
    end
  end

  describe '#apply_item' do
    it 'appends item' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      item = { id: 'item_result_1', turn_id: result[:turn_id], kind: 'assistant_text', text: 'Hello!',
               status: 'completed' }
      turns.apply_item(thread_id, item)
      expect(session_store.load_items(thread_id).any? { |i| i[:id] == 'item_result_1' }).to be true
    end
  end

  describe '#update_item' do
    it 'updates item fields' do
      result = turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      item = { id: 'item_result_1', turn_id: result[:turn_id], kind: 'assistant_text', text: 'Hello!',
               status: 'completed' }
      turns.apply_item(thread_id, item)
      expect(turns.update_item(thread_id, 'item_result_1', { text: 'Updated!' })[:text]).to eq('Updated!')
    end

    it 'returns nil for nonexistent item' do
      turns.start_turn(thread_id: thread_id, request: { prompt: 'hello' })
      expect(turns.update_item(thread_id, 'nonexistent', { text: 'x' })).to be_nil
    end
  end
end
