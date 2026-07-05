# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/append_only_session_log'

RSpec.describe DeepForge::Loop::AppendOnlySessionLog do
  subject(:log) { described_class.new(window_size) }

  let(:window_size) { 5 }

  describe '#initialize' do
    it 'sets window size' do
      expect(log).to be_a(described_class)
    end

    it 'enforces minimum window size of 1' do
      small_log = described_class.new(0)
      expect(small_log).to be_a(described_class)
    end

    it 'defaults to 1000' do
      default_log = described_class.new
      items = (1..1001).map { |i| { id: i } }
      items.each { |item| default_log.append_item(item) }
      expect(default_log.items.length).to eq(1000)
    end
  end

  describe '#ensure_session' do
    it 'creates a session if none exists' do
      session = log.ensure_session(thread_id: 't1', turn_id: 'r1')
      expect(session[:thread_id]).to eq('t1')
      expect(session[:turn_id]).to eq('r1')
      expect(session[:items]).to eq([])
      expect(session[:events]).to eq([])
    end

    it 'returns existing session on subsequent calls' do
      s1 = log.ensure_session(thread_id: 't1', turn_id: 'r1')
      s2 = log.ensure_session(thread_id: 't2', turn_id: 'r2')
      expect(s1).to equal(s2)
    end
  end

  describe '#load' do
    it 'loads an existing session' do
      existing = { thread_id: 't1', turn_id: 'r1', items: [{ id: 1 }], events: [] }
      log.load(existing)
      expect(log.current).to eq(existing)
    end
  end

  describe '#append_item' do
    it 'creates session if needed' do
      log.append_item({ id: 1, thread_id: 't1' })
      expect(log.current).not_to be_nil
      expect(log.items.length).to eq(1)
    end

    it 'appends to existing session' do
      log.load({ thread_id: 't1', turn_id: 'r1', items: [{ id: 1 }], events: [] })
      log.append_item({ id: 2 })
      expect(log.items.length).to eq(2)
      expect(log.items.last[:id]).to eq(2)
    end

    it 'evicts items beyond window size' do
      (1..10).each { |i| log.append_item({ id: i }) }
      expect(log.items.length).to eq(window_size)
      expect(log.items.first[:id]).to eq(6)
    end

    it 'returns updated session' do
      result = log.append_item({ id: 1 })
      expect(result).to equal(log.current)
    end
  end

  describe '#append_event' do
    it 'creates session if needed' do
      log.append_event({ kind: 'test', thread_id: 't1' })
      expect(log.events.length).to eq(1)
    end

    it 'evicts events beyond window size' do
      (1..10).each { |i| log.append_event({ kind: "event_#{i}" }) }
      expect(log.events.length).to eq(window_size)
    end
  end

  describe '#items' do
    it 'returns empty array when no session' do
      expect(log.items).to eq([])
    end
  end

  describe '#events' do
    it 'returns empty array when no session' do
      expect(log.events).to eq([])
    end
  end

  describe '#current' do
    it 'returns nil when no session loaded' do
      expect(log.current).to be_nil
    end
  end
end
