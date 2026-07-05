# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/inflight_tracker'

RSpec.describe DeepForge::Loop::InflightTracker do
  subject(:tracker) { described_class.new }

  describe '#begin' do
    it 'registers a new inflight record' do
      record = tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      expect(record.id).to eq('r1')
      expect(record.kind).to eq('tool')
      expect(record.thread_id).to eq('t1')
      expect(record.turn_id).to eq('r1')
      expect(record.started_at).to be_a(Integer)
    end

    it 'sets started_at automatically' do
      before = (Time.now.to_f * 1000).to_i
      record = tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      after = (Time.now.to_f * 1000).to_i
      expect(record.started_at).to be >= before
      expect(record.started_at).to be <= after
    end

    it 'allows custom started_at' do
      record = tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1', started_at: 12_345)
      expect(record.started_at).to eq(12_345)
    end
  end

  describe '#end' do
    it 'removes and returns the record' do
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      record = tracker.end('r1')
      expect(record).not_to be_nil
      expect(record.id).to eq('r1')
    end

    it 'returns nil for unknown id' do
      expect(tracker.end('unknown')).to be_nil
    end

    it 'removes from tracking' do
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      tracker.end('r1')
      expect(tracker.has?('r1')).to be(false)
    end
  end

  describe '#run' do
    it 'executes the block and cleans up' do
      result = tracker.run(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1') do
        'done'
      end
      expect(result).to eq('done')
      expect(tracker.has?('r1')).to be(false)
    end

    it 'cleans up even if block raises' do
      expect do
        tracker.run(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1') do
          raise 'boom'
        end
      end.to raise_error(RuntimeError, 'boom')
      expect(tracker.has?('r1')).to be(false)
    end
  end

  describe '#get' do
    it 'returns the record' do
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      expect(tracker.get('r1')).not_to be_nil
    end

    it 'returns nil for unknown id' do
      expect(tracker.get('unknown')).to be_nil
    end
  end

  describe '#has?' do
    it 'returns true for existing records' do
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      expect(tracker.has?('r1')).to be(true)
    end

    it 'returns false for unknown records' do
      expect(tracker.has?('unknown')).to be(false)
    end
  end

  describe '#list' do
    it 'returns all inflight records' do
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      tracker.begin(id: 'r2', kind: 'model', thread_id: 't1', turn_id: 'r2')
      expect(tracker.list.length).to eq(2)
    end

    it 'returns empty array when no records' do
      expect(tracker.list).to eq([])
    end
  end

  describe '#abort_all' do
    it 'clears all records and returns IDs with reason' do
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      tracker.begin(id: 'r2', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      result = tracker.abort_all('cancelled')
      expect(result).to contain_exactly('r1:cancelled', 'r2:cancelled')
      expect(tracker.size).to eq(0)
    end

    it 'uses default reason' do
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      result = tracker.abort_all
      expect(result).to eq(['r1:aborted'])
    end
  end

  describe '#size' do
    it 'returns the number of inflight records' do
      expect(tracker.size).to eq(0)
      tracker.begin(id: 'r1', kind: 'tool', thread_id: 't1', turn_id: 'r1')
      expect(tracker.size).to eq(1)
      tracker.end('r1')
      expect(tracker.size).to eq(0)
    end
  end
end
