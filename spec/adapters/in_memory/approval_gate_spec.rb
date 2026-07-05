# frozen_string_literal: true

require 'spec_helper'
require 'concurrent-ruby'
require_relative '../../../lib/deepforge/adapters/in_memory/approval_gate'

RSpec.describe DeepForge::Adapters::InMemory::ApprovalGate do
  subject(:gate) { described_class.new }

  describe '#request' do
    it 'stores the approval request and returns a resolvable future' do
      future = gate.request(id: 'a1', thread_id: 't1', tool_name: 'bash')
      expect(future).to be_a(Concurrent::Promises::ResolvableFuture)
      expect(gate.get('a1')).to include(id: 'a1', thread_id: 't1')
    end

    it 'rejects duplicate IDs silently (last write wins)' do
      gate.request(id: 'a1', thread_id: 't1')
      gate.request(id: 'a1', thread_id: 't2')
      expect(gate.get('a1')[:thread_id]).to eq('t2')
    end
  end

  describe '#decide' do
    before { gate.request(id: 'a1', thread_id: 't1') }

    it 'returns false when approval ID is unknown' do
      expect(gate.decide('unknown', 'allow')).to be false
    end

    it 'fulfills the future with the decision' do
      future = gate.request(id: 'a2', thread_id: 't1')
      gate.decide('a2', 'allow')
      expect(future.value).to eq('allow')
    end

    it 'sets status, decision, reason, and resolved_at on the approval' do
      gate.decide('a1', 'deny', 'not allowed')
      stored = gate.get('a1')
      expect(stored[:status]).to eq('deny')
      expect(stored[:decision]).to eq('deny')
      expect(stored[:reason]).to eq('not allowed')
      expect(stored[:resolved_at]).to be_a(String)
    end

    it 'returns true on successful decide' do
      expect(gate.decide('a1', 'allow')).to be true
    end
  end

  describe '#pending' do
    it 'returns only approvals with status pending' do
      gate.request(id: 'a1', thread_id: 't1', status: 'pending')
      gate.request(id: 'a2', thread_id: 't1', status: 'pending')
      gate.decide('a1', 'allow')

      pending = gate.pending
      expect(pending.length).to eq(1)
      expect(pending.first[:id]).to eq('a2')
    end

    it 'filters by thread_id when provided' do
      gate.request(id: 'a1', thread_id: 't1', status: 'pending')
      gate.request(id: 'a2', thread_id: 't2', status: 'pending')

      expect(gate.pending('t1').length).to eq(1)
      expect(gate.pending('t1').first[:id]).to eq('a1')
    end

    it 'returns all pending when no thread_id given' do
      gate.request(id: 'a1', thread_id: 't1', status: 'pending')
      gate.request(id: 'a2', thread_id: 't2', status: 'pending')
      expect(gate.pending.length).to eq(2)
    end

    it 'excludes approvals without status key' do
      gate.request(id: 'a1', thread_id: 't1')
      expect(gate.pending).to be_empty
    end
  end

  describe '#get' do
    it 'returns nil for unknown ID' do
      expect(gate.get('nonexistent')).to be_nil
    end

    it 'returns the full approval hash' do
      gate.request(id: 'a1', thread_id: 't1', tool_name: 'bash')
      expect(gate.get('a1')).to include(tool_name: 'bash')
    end
  end

  describe '#resolve' do
    it 'delegates to decide' do
      gate.request(id: 'a1', thread_id: 't1')
      expect(gate.resolve('a1', 'allow')).to be true
      expect(gate.get('a1')[:status]).to eq('allow')
    end
  end
end
