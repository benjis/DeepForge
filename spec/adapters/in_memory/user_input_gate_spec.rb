# frozen_string_literal: true

require 'spec_helper'
require 'concurrent-ruby'
require_relative '../../../lib/deepforge/adapters/in_memory/user_input_gate'

RSpec.describe DeepForge::Adapters::InMemory::UserInputGate do
  subject(:gate) { described_class.new }

  describe '#request' do
    it 'stores the input request and returns a resolvable future' do
      future = gate.request(id: 'u1', thread_id: 't1', kind: 'confirm')
      expect(future).to be_a(Concurrent::Promises::ResolvableFuture)
      expect(gate.get('u1')).to include(id: 'u1', thread_id: 't1')
    end
  end

  describe '#get' do
    it 'returns nil for unknown id' do
      expect(gate.get('unknown')).to be_nil
    end

    it 'returns the input request hash' do
      gate.request(id: 'u1', thread_id: 't1', kind: 'confirm')
      expect(gate.get('u1')[:kind]).to eq('confirm')
    end
  end

  describe '#resolve' do
    it 'returns false for unknown id' do
      expect(gate.resolve('unknown', { answer: 'yes' })).to be false
    end

    it 'removes the request from pending' do
      gate.request(id: 'u1', thread_id: 't1')
      gate.resolve('u1', { answer: 'yes' })
      expect(gate.get('u1')).to be_nil
    end

    it 'fulfills the future with the resolution' do
      future = gate.request(id: 'u1', thread_id: 't1')
      resolution = { answer: 'yes' }
      gate.resolve('u1', resolution)
      expect(future.value).to eq(resolution)
    end

    it 'returns true on success' do
      gate.request(id: 'u1', thread_id: 't1')
      expect(gate.resolve('u1', { answer: 'yes' })).to be true
    end
  end

  describe '#pending' do
    it 'returns all pending requests when no thread_id given' do
      gate.request(id: 'u1', thread_id: 't1')
      gate.request(id: 'u2', thread_id: 't2')
      expect(gate.pending.length).to eq(2)
    end

    it 'filters by thread_id' do
      gate.request(id: 'u1', thread_id: 't1')
      gate.request(id: 'u2', thread_id: 't2')
      expect(gate.pending('t1').length).to eq(1)
      expect(gate.pending('t1').first[:id]).to eq('u1')
    end

    it 'excludes resolved requests' do
      gate.request(id: 'u1', thread_id: 't1')
      gate.resolve('u1', { answer: 'yes' })
      expect(gate.pending).to be_empty
    end
  end

  describe '#reset' do
    it 'rejects all pending futures and clears state' do
      future = gate.request(id: 'u1', thread_id: 't1')
      gate.reset

      expect(future).to be_rejected
      expect(gate.pending).to be_empty
    end

    it 'clears the requests hash' do
      gate.request(id: 'u1', thread_id: 't1')
      gate.reset
      expect(gate.get('u1')).to be_nil
    end
  end
end
