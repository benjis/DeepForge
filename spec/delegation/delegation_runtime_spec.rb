# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe DeepForge::Delegation::DelegationRuntime do
  let(:store) { DeepForge::Delegation::FileDelegationStore.new(Dir.mktmpdir) }
  let(:config) { { enabled: true, max_parallel: 2, max_child_runs: 10 } }

  describe 'ChildRunUsage' do
    it 'has a default factory' do
      usage = DeepForge::Delegation::ChildRunUsage.default
      expect(usage.prompt_tokens).to eq(0)
      expect(usage.completion_tokens).to eq(0)
      expect(usage.total_tokens).to eq(0)
    end
  end

  describe 'ChildRunRecord' do
    it 'creates from hash' do
      record = DeepForge::Delegation::ChildRunRecord.from_hash(
        id: 'c1',
        parent_thread_id: 't1',
        status: 'completed',
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
      )
      expect(record.id).to eq('c1')
      expect(record.usage.prompt_tokens).to eq(10)
      expect(record.status).to eq('completed')
    end

    it 'converts to hash' do
      record = DeepForge::Delegation::ChildRunRecord.from_hash(
        id: 'c1',
        parent_thread_id: 't1',
        status: 'completed',
        usage: { prompt_tokens: 10 }
      )
      hash = record.to_hash
      expect(hash[:id]).to eq('c1')
      expect(hash[:status]).to eq('completed')
    end
  end

  describe 'FileDelegationStore' do
    it 'upserts and lists records' do
      record = DeepForge::Delegation::ChildRunRecord.from_hash(
        id: 'c1',
        parent_thread_id: 't1',
        status: 'running',
        usage: {}
      )
      store.upsert(record)

      records = store.list
      expect(records.length).to eq(1)
      expect(records.first.id).to eq('c1')
    end

    it 'filters by parent_thread_id' do
      store.upsert(DeepForge::Delegation::ChildRunRecord.from_hash(
                     id: 'c1', parent_thread_id: 't1', status: 'running', usage: {}
                   ))
      store.upsert(DeepForge::Delegation::ChildRunRecord.from_hash(
                     id: 'c2', parent_thread_id: 't2', status: 'running', usage: {}
                   ))

      records = store.list(parent_thread_id: 't1')
      expect(records.length).to eq(1)
      expect(records.first.id).to eq('c1')
    end
  end

  describe '#run_child' do
    it 'raises when delegation is disabled' do
      disabled_config = { enabled: false, max_parallel: 1, max_child_runs: 10 }
      runtime = described_class.new(config: disabled_config, store: store)

      expect do
        runtime.run_child(parent_thread_id: 't1', prompt: 'test')
      end.to raise_error('delegation is disabled by config')
    end

    it 'executes child and returns completed record' do
      executor = ->(_input) { { summary: 'done', usage: DeepForge::Delegation::ChildRunUsage.default } }
      runtime = described_class.new(config: config, store: store, executor: executor)

      record = runtime.run_child(
        parent_thread_id: 't1',
        parent_turn_id: 'turn1',
        prompt: 'test prompt'
      )

      expect(record.status).to eq('completed')
      expect(record.summary).to eq('done')
      expect(record.parent_thread_id).to eq('t1')
    end

    it 'records failure when executor raises' do
      executor = ->(_input) { raise 'boom' }
      runtime = described_class.new(config: config, store: store, executor: executor)

      record = runtime.run_child(
        parent_thread_id: 't1',
        prompt: 'test'
      )

      expect(record.status).to eq('failed')
      expect(record.error).to eq('boom')
    end
  end

  describe '#diagnostics' do
    it 'returns enabled status and child runs' do
      runtime = described_class.new(config: config, store: store)
      diag = runtime.diagnostics
      expect(diag[:enabled]).to be true
      expect(diag[:child_runs]).to be_an(Array)
      expect(diag[:active]).to eq(0)
    end
  end

  describe '.aggregate_child_runs' do
    it 'aggregates records by label and model' do
      records = [
        DeepForge::Delegation::ChildRunRecord.from_hash(
          id: 'c1', label: 'task1', model: 'm1', status: 'completed',
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        ),
        DeepForge::Delegation::ChildRunRecord.from_hash(
          id: 'c2', label: 'task1', model: 'm1', status: 'failed',
          usage: { prompt_tokens: 8, completion_tokens: 3, total_tokens: 11 }
        )
      ]

      aggregates = DeepForge::Delegation.aggregate_child_runs(records)
      expect(aggregates.length).to eq(1)
      expect(aggregates.first.runs).to eq(2)
      expect(aggregates.first.completed).to eq(1)
      expect(aggregates.first.failed).to eq(1)
      expect(aggregates.first.total_tokens).to eq(26)
    end

    it 'returns empty array for no records' do
      expect(DeepForge::Delegation.aggregate_child_runs([])).to eq([])
    end
  end
end
