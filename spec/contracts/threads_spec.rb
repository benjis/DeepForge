# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'ThreadStatus constants' do
    it 'defines all statuses' do
      expect(described_class::ThreadStatus::IDLE).to eq('idle')
      expect(described_class::ThreadStatus::RUNNING).to eq('running')
      expect(described_class::ThreadStatus::ARCHIVED).to eq('archived')
      expect(described_class::ThreadStatus::DELETED).to eq('deleted')
    end
  end

  describe 'ThreadMode constants' do
    it 'defines AGENT and PLAN' do
      expect(described_class::ThreadMode::AGENT).to eq('agent')
      expect(described_class::ThreadMode::PLAN).to eq('plan')
    end
  end

  describe 'ThreadRelation constants' do
    it 'defines PRIMARY, FORK, SIDE' do
      expect(described_class::ThreadRelation::PRIMARY).to eq('primary')
      expect(described_class::ThreadRelation::FORK).to eq('fork')
      expect(described_class::ThreadRelation::SIDE).to eq('side')
    end
  end

  describe 'ThreadTodoStatus constants' do
    it 'defines PENDING, IN_PROGRESS, COMPLETED' do
      expect(described_class::ThreadTodoStatus::PENDING).to eq('pending')
      expect(described_class::ThreadTodoStatus::IN_PROGRESS).to eq('in_progress')
      expect(described_class::ThreadTodoStatus::COMPLETED).to eq('completed')
    end
  end

  describe '.validate_todo_list' do
    it 'passes when zero in_progress items' do
      list = described_class::ThreadTodoList.new(
        thread_id: 't1', items: [
          described_class::ThreadTodoItem.new(id: 'x1', content: 'task', status: 'pending')
        ], updated_at: '2025-01-01T00:00:00Z'
      )
      expect { described_class.validate_todo_list(list) }.not_to raise_error
    end

    it 'passes when exactly one in_progress item' do
      list = described_class::ThreadTodoList.new(
        thread_id: 't1', items: [
          described_class::ThreadTodoItem.new(id: 'x1', content: 'task', status: 'in_progress')
        ], updated_at: '2025-01-01T00:00:00Z'
      )
      expect { described_class.validate_todo_list(list) }.not_to raise_error
    end

    it 'raises when more than one in_progress item' do
      list = described_class::ThreadTodoList.new(
        thread_id: 't1', items: [
          described_class::ThreadTodoItem.new(id: 'x1', content: 'a', status: 'in_progress'),
          described_class::ThreadTodoItem.new(id: 'x2', content: 'b', status: 'in_progress')
        ], updated_at: '2025-01-01T00:00:00Z'
      )
      expect { described_class.validate_todo_list(list) }.to raise_error(ArgumentError, /at most one/)
    end
  end

  describe 'SetThreadGoalRequest' do
    it 'validates when objective provided' do
      req = described_class::SetThreadGoalRequest.new(objective: 'do things')
      expect(described_class::SetThreadGoalRequest.validate(req)).to be(true)
    end

    it 'raises when all fields nil' do
      expect do
        described_class::SetThreadGoalRequest.validate({})
      end.to raise_error(ArgumentError, /At least one/)
    end
  end

  describe 'UpdateThreadRequest' do
    it 'validates when at least one field provided' do
      req = described_class::UpdateThreadRequest.new(title: 'new title')
      expect(described_class::UpdateThreadRequest.validate(req)).to be(true)
    end

    it 'raises when all fields nil' do
      expect do
        described_class::UpdateThreadRequest.validate({})
      end.to raise_error(ArgumentError, /At least one field/)
    end
  end

  describe 'ThreadRecord' do
    it 'creates with all expected fields' do
      thread = described_class::ThreadRecord.new(
        id: 't1', title: 'Test', workspace: '/ws', model: 'm',
        mode: 'agent', status: 'idle', turns: []
      )
      expect(thread.id).to eq('t1')
      expect(thread.turns).to eq([])
    end
  end

  describe 'ThreadSummary' do
    it 'creates with keyword init' do
      summary = described_class::ThreadSummary.new(id: 't1', title: 'T')
      expect(summary.id).to eq('t1')
    end
  end
end
