# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/in_memory/event_bus'

RSpec.describe DeepForge::Adapters::InMemory::EventBus do
  subject(:bus) { described_class.new }

  describe '#publish' do
    it 'stores events by thread_id' do
      bus.publish(thread_id: 't1', seq: 1, kind: 'text')
      bus.publish(thread_id: 't1', seq: 2, kind: 'text')
      expect(bus.snapshot_since('t1', 0).length).to eq(2)
    end

    it 'does not cross thread boundaries' do
      bus.publish(thread_id: 't1', seq: 1, kind: 'text')
      bus.publish(thread_id: 't2', seq: 1, kind: 'text')
      expect(bus.snapshot_since('t1', 0).length).to eq(1)
      expect(bus.snapshot_since('t2', 0).length).to eq(1)
    end

    it 'notifies subscribers' do
      received = []
      bus.subscribe('t1', proc { |e| received << e })
      bus.publish(thread_id: 't1', seq: 1, kind: 'text')
      expect(received.length).to eq(1)
      expect(received.first[:seq]).to eq(1)
    end

    it 'does not notify subscribers of other threads' do
      received = []
      bus.subscribe('t1', proc { |e| received << e })
      bus.publish(thread_id: 't2', seq: 1, kind: 'text')
      expect(received).to be_empty
    end

    it 'isolates subscriber exceptions' do
      bus.subscribe('t1', proc { raise 'boom' })
      expect { bus.publish(thread_id: 't1', seq: 1) }.not_to raise_error
    end
  end

  describe '#subscribe' do
    it 'returns a callable unsubscribe function' do
      received = []
      unsub = bus.subscribe('t1', proc { |e| received << e })
      bus.publish(thread_id: 't1', seq: 1)
      expect(received.length).to eq(1)

      unsub.call
      bus.publish(thread_id: 't1', seq: 2)
      expect(received.length).to eq(1)
    end

    it 'supports multiple subscribers on the same thread' do
      r1 = []
      r2 = []
      bus.subscribe('t1', proc { |e| r1 << e })
      bus.subscribe('t1', proc { |e| r2 << e })
      bus.publish(thread_id: 't1', seq: 1)
      expect(r1.length).to eq(1)
      expect(r2.length).to eq(1)
    end
  end

  describe '#snapshot_since' do
    it 'returns events with seq greater than since_seq' do
      bus.publish(thread_id: 't1', seq: 1, kind: 'a')
      bus.publish(thread_id: 't1', seq: 2, kind: 'b')
      bus.publish(thread_id: 't1', seq: 3, kind: 'c')

      result = bus.snapshot_since('t1', 1)
      expect(result.map { |e| e[:seq] }).to eq([2, 3])
    end

    it 'returns empty array for unknown thread' do
      expect(bus.snapshot_since('unknown', 0)).to eq([])
    end

    it 'returns empty array when since_seq is >= all seqs' do
      bus.publish(thread_id: 't1', seq: 1)
      expect(bus.snapshot_since('t1', 5)).to eq([])
    end
  end

  describe '#highest_seq' do
    it 'returns 0 for empty thread' do
      expect(bus.highest_seq('t1')).to eq(0)
    end

    it 'returns the maximum seq' do
      bus.publish(thread_id: 't1', seq: 3)
      bus.publish(thread_id: 't1', seq: 1)
      bus.publish(thread_id: 't1', seq: 5)
      expect(bus.highest_seq('t1')).to eq(5)
    end
  end

  describe '#allocate_seq' do
    it 'starts at highest_seq + 1' do
      bus.publish(thread_id: 't1', seq: 10)
      expect(bus.allocate_seq('t1')).to eq(11)
    end

    it 'increments on each call' do
      s1 = bus.allocate_seq('t1')
      s2 = bus.allocate_seq('t1')
      expect(s2).to eq(s1 + 1)
    end

    it 'starts at 1 for a fresh thread' do
      expect(bus.allocate_seq('new_thread')).to eq(1)
    end
  end

  describe '#reset' do
    it 'clears all events, subscribers, and sequences' do
      bus.publish(thread_id: 't1', seq: 1)
      bus.subscribe('t1', proc { |_| })
      bus.allocate_seq('t1')

      bus.reset

      expect(bus.snapshot_since('t1', 0)).to be_empty
      expect(bus.highest_seq('t1')).to eq(0)
    end
  end
end
