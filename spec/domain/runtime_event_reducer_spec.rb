# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  describe 'EventSourcedTurnStatus constants' do
    it 'defines all statuses' do
      expect(DeepForge::Domain::EventSourcedTurnStatus::UNKNOWN).to eq('unknown')
      expect(DeepForge::Domain::EventSourcedTurnStatus::RUNNING).to eq('running')
      expect(DeepForge::Domain::EventSourcedTurnStatus::COMPLETED).to eq('completed')
      expect(DeepForge::Domain::EventSourcedTurnStatus::FAILED).to eq('failed')
      expect(DeepForge::Domain::EventSourcedTurnStatus::ABORTED).to eq('aborted')
    end
  end

  describe '.create_runtime_event_projection' do
    it 'creates a projection with default values' do
      proj = described_class.create_runtime_event_projection(thread_id: 't1')
      expect(proj.thread_id).to eq('t1')
      expect(proj.last_seq).to eq(0)
      expect(proj.turns).to eq([])
      expect(proj.items).to eq([])
      expect(proj.child_runs).to eq([])
      expect(proj.compactions).to eq([])
      expect(proj.errors).to eq([])
    end
  end

  describe '.replay_runtime_events' do
    it 'returns empty projection for no events' do
      proj = described_class.replay_runtime_events([])
      expect(proj.last_seq).to eq(0)
    end

    it 'applies turn_started event' do
      events = [DeepForge::Contracts::TurnLifecycleEvent.new(
        seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
        turn_id: 'tr1', kind: 'turn_started'
      )]
      proj = described_class.replay_runtime_events(events)
      expect(proj.turns.size).to eq(1)
      expect(proj.turns.first.status).to eq('running')
    end

    it 'applies turn_completed event' do
      events = [
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_started'
        ),
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 2, timestamp: '2025-01-01T00:00:01Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_completed'
        )
      ]
      proj = described_class.replay_runtime_events(events)
      expect(proj.turns.first.status).to eq('completed')
      expect(proj.turns.first.finished_at).to match(/\d{4}/)
    end

    it 'applies turn_failed event' do
      events = [
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_started'
        ),
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 2, timestamp: '2025-01-01T00:00:01Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_failed'
        )
      ]
      proj = described_class.replay_runtime_events(events)
      expect(proj.turns.first.status).to eq('failed')
    end

    it 'applies turn_aborted event' do
      events = [
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_started'
        ),
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 2, timestamp: '2025-01-01T00:00:01Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_aborted'
        )
      ]
      proj = described_class.replay_runtime_events(events)
      expect(proj.turns.first.status).to eq('aborted')
    end

    it 'applies turn_steered event' do
      events = [
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_started'
        ),
        DeepForge::Contracts::TurnLifecycleEvent.new(
          seq: 2, timestamp: '2025-01-01T00:00:01Z', thread_id: 't1',
          turn_id: 'tr1', kind: 'turn_steered', text: 'new direction'
        )
      ]
      proj = described_class.replay_runtime_events(events)
      expect(proj.turns.first.steering).to eq(['new direction'])
    end

    it 'applies thread_updated event with title and status' do
      events = [DeepForge::Contracts::ThreadLifecycleEvent.new(
        seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
        kind: 'thread_updated', title: 'New Title', status: 'running'
      )]
      proj = described_class.replay_runtime_events(events)
      expect(proj.title).to eq('New Title')
      expect(proj.thread_status).to eq('running')
    end

    it 'applies error event' do
      event = DeepForge::Contracts::ErrorEvent.new(
        seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
        turn_id: 'tr1', item_id: 'e1', kind: 'error',
        message: 'boom', code: 'E1'
      )
      proj = described_class.replay_runtime_events([event])
      expect(proj.errors.size).to eq(1)
      expect(proj.errors.first.message).to eq('boom')
      expect(proj.items.size).to eq(1)
      expect(proj.items.first.kind).to eq('error')
    end

    it 'skips events with seq <= last_seq' do
      e1 = DeepForge::Contracts::TurnLifecycleEvent.new(
        seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
        turn_id: 'tr1', kind: 'turn_started'
      )
      proj = described_class.replay_runtime_events([e1])
      e1_dup = DeepForge::Contracts::TurnLifecycleEvent.new(
        seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
        turn_id: 'tr1', kind: 'turn_completed'
      )
      proj2 = described_class.apply_runtime_event(proj, e1_dup)
      expect(proj2.last_seq).to eq(1)
    end

    it 'sorts events by seq before applying' do
      e1 = DeepForge::Contracts::TurnLifecycleEvent.new(
        seq: 2, timestamp: '2025-01-01T00:00:01Z', thread_id: 't1',
        turn_id: 'tr1', kind: 'turn_completed'
      )
      e2 = DeepForge::Contracts::TurnLifecycleEvent.new(
        seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
        turn_id: 'tr1', kind: 'turn_started'
      )
      proj = described_class.replay_runtime_events([e1, e2])
      expect(proj.turns.first.status).to eq('completed')
    end
  end

  describe '.apply_runtime_event' do
    it 'returns projection unchanged when event seq <= last_seq' do
      proj = described_class.create_runtime_event_projection
      event = DeepForge::Contracts::TurnLifecycleEvent.new(
        seq: 0, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
        kind: 'turn_started'
      )
      result = described_class.apply_runtime_event(proj, event)
      expect(result).to equal(proj)
    end
  end
end
