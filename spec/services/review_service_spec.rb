# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/two_arg_event_bus'

RSpec.describe DeepForge::Services::ReviewService do
  describe '.summarize_review_turn' do
    it 'skips non-assistant_text items' do
      items = [{ turn_id: 't1', kind: 'user_message', text: 'Hello' }]
      expect(described_class.summarize_review_turn(items, 't1')).to eq('')
    end

    it 'returns empty string for no matching items' do
      expect(described_class.summarize_review_turn([], 't1')).to eq('')
    end
  end

  describe '#run_review' do
    subject(:review_service) { described_class.new(deps) }

    let(:thread_store) { DeepForge::Adapters::Memory::AgentThreadStore.new }
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

    let(:turn_service) do
      DeepForge::Services::DialogueTurnService.new(
        thread_store: thread_store, session_store: session_store, events: events,
        inflight: inflight, steering: steering, compactor: compactor, ids: ids, now_iso: now_iso
      )
    end

    let(:deps) { { turns: turn_service, thread_store: thread_store, now_iso: now_iso, default_model: 'test-model' } }

    before do
      thread_store.upsert({
                            id: 'thr_review1', title: 'Review Thread', workspace: '/tmp',
                            model: 'test-model', mode: 'agent', status: 'idle', turns: [],
                            created_at: now_iso.call, updated_at: now_iso.call
                          })
    end

    it 'returns "failed" when no abort controller exists' do
      result = review_service.run_review(
        thread_id: 'thr_review1', turn_id: 'nonexistent_turn',
        review_item_id: 'ri_1', target: { type: 'file', path: 'test.rb' }
      )
      expect(result).to eq('failed')
    end
  end
end
