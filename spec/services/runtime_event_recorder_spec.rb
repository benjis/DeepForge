# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/two_arg_event_bus'

RSpec.describe DeepForge::Services::RuntimeEventRecorder do
  subject(:recorder) do
    described_class.new(event_bus: event_bus, session_store: session_store, allocate_seq: seq_counter, now_iso: now_iso)
  end

  let(:inner_event_bus) { DeepForge::Adapters::InMemory::EventBus.new }
  let(:event_bus) { TwoArgEventBus.new(inner_event_bus) }
  let(:session_store) { DeepForge::Adapters::InMemory::SessionStore.new }
  let(:now_iso) { -> { '2024-01-15T12:00:00Z' } }
  let(:seq_counter) { ->(_tid) { 1 } }

  describe '#record' do
    it 'publishes and persists a valid event' do
      event = recorder.record(thread_id: 't1', kind: 'thread_created', title: 'Test')
      expect(event[:seq]).to be >= 1
      expect(event[:timestamp]).to eq('2024-01-15T12:00:00Z')
      expect(event[:kind]).to eq('thread_created')
      expect(event[:thread_id]).to eq('t1')
    end

    it 'publishes to the event bus' do
      recorded = []
      inner_event_bus.subscribe('t1', ->(e) { recorded << e })
      recorder.record(thread_id: 't1', kind: 'thread_created')
      expect(recorded.length).to eq(1)
    end

    it 'persists to session store' do
      recorder.record(thread_id: 't1', kind: 'thread_created')
      expect(session_store.load_events_since('t1', 0).length).to eq(1)
    end

    it 'uses seq from draft if provided' do
      expect(recorder.record(thread_id: 't1', kind: 'thread_created', seq: 42)[:seq]).to eq(42)
    end

    it 'uses timestamp from draft if provided' do
      event = recorder.record(thread_id: 't1', kind: 'thread_created', timestamp: '2024-06-01T00:00:00Z')
      expect(event[:timestamp]).to eq('2024-06-01T00:00:00Z')
    end

    it 'uses max of allocated_seq and persisted+1' do
      recorder.record(thread_id: 't1', kind: 'thread_created')
      expect(recorder.record(thread_id: 't1', kind: 'thread_created')[:seq]).to eq(2)
    end

    it 'requires turn_id for turn lifecycle events' do
      %w[turn_started turn_completed turn_failed turn_aborted turn_steered].each do |kind|
        expect do
          recorder.record(thread_id: 't1', kind: kind)
        end.to raise_error(ArgumentError, /requires a non-empty turn_id/)
      end
    end

    it 'allows valid non-turn event kinds' do
      %w[thread_created thread_updated usage error heartbeat].each do |kind|
        expect(recorder.record(thread_id: 't1', kind: kind)[:kind]).to eq(kind)
      end
    end
  end

  describe 'validation' do
    it 'raises when thread_id is nil or empty' do
      expect { recorder.record(thread_id: nil, kind: 'thread_created') }.to raise_error(ArgumentError)
      expect { recorder.record(thread_id: '', kind: 'thread_created') }.to raise_error(ArgumentError)
    end

    it 'raises when kind is nil or empty' do
      expect { recorder.record(thread_id: 't1', kind: nil) }.to raise_error(ArgumentError)
      expect { recorder.record(thread_id: 't1', kind: '') }.to raise_error(ArgumentError)
    end

    it 'raises for unknown event kind' do
      expect { recorder.record(thread_id: 't1', kind: 'unknown') }.to raise_error(ArgumentError, /Unknown event kind/)
    end
  end
end
