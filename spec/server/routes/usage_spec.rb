# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/routes/usage'

RSpec.describe DeepForge::Server::Routes::Usage do
  describe '.diff_usage' do
    it 'calculates the difference between two usage snapshots' do
      current = { promptTokens: 100, completionTokens: 50, totalTokens: 150, turns: 3 }
      previous = { promptTokens: 80, completionTokens: 30, totalTokens: 110, turns: 2 }

      result = described_class.diff_usage(current, previous)
      expect(result).to eq({
                             promptTokens: 20,
                             completionTokens: 20,
                             totalTokens: 40,
                             turns: 1
                           })
    end

    it 'returns zeros when current equals previous' do
      usage = { promptTokens: 100, completionTokens: 50, totalTokens: 150, turns: 3 }
      result = described_class.diff_usage(usage, usage)
      expect(result[:promptTokens]).to eq(0)
      expect(result[:completionTokens]).to eq(0)
      expect(result[:turns]).to eq(0)
    end

    it 'never returns negative values' do
      current = { promptTokens: 10, completionTokens: 5, totalTokens: 15, turns: 1 }
      previous = { promptTokens: 100, completionTokens: 50, totalTokens: 150, turns: 10 }

      result = described_class.diff_usage(current, previous)
      expect(result[:promptTokens]).to eq(0)
      expect(result[:completionTokens]).to eq(0)
      expect(result[:turns]).to eq(0)
    end
  end

  describe '.diff_number' do
    it 'returns the positive difference' do
      expect(described_class.diff_number(10, 3)).to eq(7)
    end

    it 'returns 0 when current is less than previous' do
      expect(described_class.diff_number(3, 10)).to eq(0)
    end

    it 'returns 0 when values are equal' do
      expect(described_class.diff_number(5, 5)).to eq(0)
    end
  end

  describe '.has_usage?' do
    it 'returns true when promptTokens is positive' do
      expect(described_class.has_usage?({ promptTokens: 1, completionTokens: 0, totalTokens: 0, turns: 0 })).to be true
    end

    it 'returns false when all values are zero' do
      expect(described_class.has_usage?({ promptTokens: 0, completionTokens: 0, totalTokens: 0, turns: 0 })).to be false
    end
  end

  describe '.empty_usage_snapshot' do
    it 'returns all zeros' do
      snapshot = described_class.empty_usage_snapshot
      expect(snapshot).to eq({ promptTokens: 0, completionTokens: 0, totalTokens: 0, turns: 0 })
    end
  end

  describe '.build_thread_usage_response' do
    it 'groups usage records by thread' do
      records = [
        { thread_id: 't1', usage: { promptTokens: 10, completionTokens: 5, totalTokens: 15, turns: 1 } },
        { thread_id: 't1', usage: { promptTokens: 20, completionTokens: 10, totalTokens: 30, turns: 2 } },
        { thread_id: 't2', usage: { promptTokens: 5, completionTokens: 3, totalTokens: 8, turns: 1 } }
      ]

      result = described_class.build_thread_usage_response(records)
      expect(result).to have_key('t1')
      expect(result).to have_key('t2')
      expect(result['t1'][:promptTokens]).to eq(30)
      expect(result['t1'][:completionTokens]).to eq(15)
      expect(result['t2'][:promptTokens]).to eq(5)
    end
  end

  describe '.build_daily_usage_response' do
    it 'groups usage records by day' do
      records = [
        { completedAt: '2024-01-01T10:00:00Z',
          usage: { promptTokens: 10, completionTokens: 5, totalTokens: 15, turns: 1 } },
        { completedAt: '2024-01-01T15:00:00Z',
          usage: { promptTokens: 20, completionTokens: 10, totalTokens: 30, turns: 2 } },
        { completedAt: '2024-01-02T10:00:00Z',
          usage: { promptTokens: 5, completionTokens: 3, totalTokens: 8, turns: 1 } }
      ]

      result = described_class.build_daily_usage_response(records, {})
      expect(result['2024-01-01'][:promptTokens]).to eq(30)
      expect(result['2024-01-02'][:promptTokens]).to eq(5)
    end
  end

  describe '.build_model_usage_response' do
    it 'groups usage records by model' do
      records = [
        { model: 'deepseek-chat', usage: { promptTokens: 10, completionTokens: 5, totalTokens: 15, turns: 1 } },
        { model: 'gpt-4', usage: { promptTokens: 20, completionTokens: 10, totalTokens: 30, turns: 2 } }
      ]

      result = described_class.build_model_usage_response(records, {})
      expect(result['deepseek-chat'][:promptTokens]).to eq(10)
      expect(result['gpt-4'][:promptTokens]).to eq(20)
    end
  end

  describe '.usage_record_model' do
    it 'returns the model from the event if present' do
      thread = { model: 'thread-model', turns: [] }
      event = { model: 'event-model', turnId: 't1' }
      expect(described_class.usage_record_model(thread, event)).to eq('event-model')
    end

    it 'returns the thread model as fallback' do
      thread = { model: 'thread-model', turns: [] }
      event = { model: nil, turnId: nil }
      expect(described_class.usage_record_model(thread, event)).to eq('thread-model')
    end

    it 'returns unknown when no model found' do
      thread = { model: nil, turns: [] }
      expect(described_class.usage_record_model(thread)).to eq('unknown')
    end
  end
end
