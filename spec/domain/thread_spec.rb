# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  describe '.create_thread_record' do
    it 'creates a thread with default mode, status, and policy' do
      thread = described_class.create_thread_record(id: 't1', title: 'My Thread')
      expect(thread.id).to eq('t1')
      expect(thread.title).to eq('My Thread')
      expect(thread.mode).to eq('agent')
      expect(thread.status).to eq('idle')
      expect(thread.approval_policy).to eq('on-request')
      expect(thread.sandbox_mode).to eq('workspace-write')
      expect(thread.relation).to eq('primary')
      expect(thread.turns).to eq([])
      expect(thread.created_at).to match(/\d{4}/)
    end

    it 'uses provided values over defaults' do
      thread = described_class.create_thread_record(
        id: 't1', title: 'Plan', mode: 'plan', status: 'running',
        approval_policy: 'never', sandbox_mode: 'read-only', relation: 'fork'
      )
      expect(thread.mode).to eq('plan')
      expect(thread.status).to eq('running')
      expect(thread.approval_policy).to eq('never')
      expect(thread.sandbox_mode).to eq('read-only')
      expect(thread.relation).to eq('fork')
    end

    it 'accepts optional goal, todos, cost budget' do
      thread = described_class.create_thread_record(
        id: 't1', title: 'T', goal: 'fix bug', todos: [], cost_budget_usd: 5.0
      )
      expect(thread.goal).to eq('fix bug')
      expect(thread.cost_budget_usd).to eq(5.0)
    end
  end

  describe '.touch_thread' do
    it 'updates the updated_at timestamp' do
      thread = described_class.create_thread_record(id: 't1', title: 'T')
      original_updated = thread.updated_at
      sleep 0.001
      touched = described_class.touch_thread(thread)
      expect(touched.updated_at).to be >= original_updated
    end

    it 'uses provided updated_at' do
      thread = described_class.create_thread_record(id: 't1', title: 'T')
      ts = '2030-01-01T00:00:00Z'
      touched = described_class.touch_thread(thread, updated_at: ts)
      expect(touched.updated_at).to eq(ts)
    end
  end

  describe '.to_thread_summary' do
    it 'creates a ThreadSummary from ThreadRecord' do
      thread = described_class.create_thread_record(
        id: 't1', title: 'T', workspace: '/ws', model: 'deepseek-chat'
      )
      summary = described_class.to_thread_summary(thread)
      expect(summary).to be_a(DeepForge::Contracts::ThreadSummary)
      expect(summary.id).to eq('t1')
      expect(summary.title).to eq('T')
      expect(summary.workspace).to eq('/ws')
      expect(summary.model).to eq('deepseek-chat')
    end

    it 'copies all relevant fields' do
      thread = described_class.create_thread_record(
        id: 't1', title: 'T', cost_budget_usd: 10.0, goal: 'do things'
      )
      summary = described_class.to_thread_summary(thread)
      expect(summary.cost_budget_usd).to eq(10.0)
      expect(summary.goal).to eq('do things')
    end
  end
end
