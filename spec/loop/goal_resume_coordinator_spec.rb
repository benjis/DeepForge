# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/goal_resume_coordinator'

RSpec.describe DeepForge::Loop::GoalResumeCoordinator do
  subject(:coordinator) { described_class.new(deps) }

  let(:launches) { [] }
  let(:goal_keys) { {} }
  let(:busy_threads) { Set.new }
  let(:timers) { [] }
  let(:logs) { [] }

  let(:deps) do
    described_class::GoalResumeCoordinatorDeps.new(
      launch: ->(tid) { launches << tid },
      get_active_goal_key: ->(tid) { goal_keys[tid] },
      is_thread_busy: ->(tid) { busy_threads.include?(tid) },
      set_timer: lambda { |fn, delay_ms|
        timers << { fn: fn, delay_ms: delay_ms }
        described_class::GoalResumeTimer.new(lambda {
        })
      },
      log: ->(msg) { logs << msg },
      max_no_progress_attempts: 3,
      base_delay_ms: 100,
      max_delay_ms: 1000
    )
  end

  describe '#note_goal_turn_failed' do
    it 'schedules recovery on first failure' do
      goal_keys['t1'] = 'g1'
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      expect(result).to eq('scheduled')
      expect(timers.length).to eq(1)
    end

    it 'resets streak when progress was made' do
      goal_keys['t1'] = 'g1'
      3.times { coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false) }
      coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: true)
      # Should still be scheduled (streak reset)
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      expect(result).to eq('scheduled')
    end

    it 'returns exhausted when budget exceeded' do
      goal_keys['t1'] = 'g1'
      3.times { coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false) }
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      expect(result).to eq('exhausted')
    end

    it 'cancels previous timer on new failure' do
      goal_keys['t1'] = 'g1'
      coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      # Two timers created, but first should have been cancelled
      expect(timers.length).to eq(2)
    end

    it 'returns skipped when shutting down' do
      coordinator.shutdown
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      expect(result).to eq('skipped')
    end

    it 'resets state when goal_key changes' do
      goal_keys['t1'] = 'g1'
      3.times { coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false) }
      goal_keys['t1'] = 'g2'
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g2', made_progress: false)
      expect(result).to eq('scheduled')
    end
  end

  describe '#resume_interrupted' do
    it 'launches when goal is active and thread is idle' do
      goal_keys['t1'] = 'g1'
      result = coordinator.resume_interrupted('t1')
      expect(result).to be(true)
      expect(launches).to eq(['t1'])
    end

    it 'returns false when no active goal' do
      goal_keys['t1'] = nil
      expect(coordinator.resume_interrupted('t1')).to be(false)
    end

    it 'returns false when thread is busy' do
      goal_keys['t1'] = 'g1'
      busy_threads.add('t1')
      expect(coordinator.resume_interrupted('t1')).to be(false)
    end

    it 'returns false when shutting down' do
      coordinator.shutdown
      expect(coordinator.resume_interrupted('t1')).to be(false)
    end

    it 'resets attempt counter' do
      goal_keys['t1'] = 'g1'
      3.times { coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false) }
      coordinator.resume_interrupted('t1')
      # After resume, streak should be reset
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      expect(result).to eq('scheduled')
    end

    it 'handles errors gracefully' do
      deps.launch = ->(_tid) { raise 'boom' }
      goal_keys['t1'] = 'g1'
      result = coordinator.resume_interrupted('t1')
      expect(result).to be(false)
      expect(logs.any? { |l| l.include?('boom') }).to be(true)
    end
  end

  describe '#clear' do
    it 'cancels timer and removes state' do
      goal_keys['t1'] = 'g1'
      coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      coordinator.clear('t1')
      # After clearing, a new failure should start fresh
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      expect(result).to eq('scheduled')
    end

    it 'does nothing for unknown thread' do
      expect { coordinator.clear('unknown') }.not_to raise_error
    end
  end

  describe '#shutdown' do
    it 'cancels all timers and clears state' do
      goal_keys['t1'] = 'g1'
      coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      coordinator.shutdown
      result = coordinator.note_goal_turn_failed(thread_id: 't1', goal_key: 'g1', made_progress: false)
      expect(result).to eq('skipped')
    end
  end
end
