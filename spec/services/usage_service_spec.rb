# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Services::UsageService do
  subject(:service) { described_class.new }

  let(:usage_hash) do
    {
      prompt_tokens: 100, completion_tokens: 50, total_tokens: 150,
      cached_tokens: 20, cache_hit_tokens: 15, cache_miss_tokens: 5,
      turns: 1, cost_usd: 0.01, cost_cny: 0.07,
      cache_savings_usd: 0.001, cache_savings_cny: 0.007,
      token_economy_savings_tokens: 0, token_economy_savings_usd: 0, token_economy_savings_cny: 0
    }
  end

  describe '#record' do
    it 'accumulates usage counters per thread' do
      service.record('t1', usage_hash)
      service.record('t1', usage_hash)
      result = service.for_thread('t1')
      expect(result[:prompt_tokens]).to eq(200)
      expect(result[:completion_tokens]).to eq(100)
      expect(result[:total_tokens]).to eq(300)
      expect(result[:turns]).to eq(2)
    end

    it 'tracks cache data separately' do
      service.record('t1', usage_hash)
      cache = service.cache_snapshot('t1')
      expect(cache[:cache_hit_tokens]).to eq(15)
      expect(cache[:cache_miss_tokens]).to eq(5)
    end

    it 'returns the updated counter' do
      expect(service.record('t1', usage_hash)[:prompt_tokens]).to eq(100)
    end
  end

  describe '#record_token_economy_savings' do
    it 'accumulates savings' do
      service.seed_thread('t1', usage_hash)
      service.record_token_economy_savings('t1', token_economy_savings_tokens: 50, token_economy_savings_usd: 0.05)
      result = service.for_thread('t1')
      expect(result[:token_economy_savings_tokens]).to eq(50)
      expect(result[:token_economy_savings_usd]).to eq(0.05)
    end

    it 'works for new thread' do
      result = service.record_token_economy_savings('new', token_economy_savings_tokens: 10)
      expect(result[:token_economy_savings_tokens]).to eq(10)
    end
  end

  describe '#seed_thread' do
    it 'initializes counters with provided usage' do
      result = service.seed_thread('t1', usage_hash)
      expect(result[:prompt_tokens]).to eq(100)
    end

    it 'merges with existing counters' do
      service.record('t1', usage_hash)
      service.seed_thread('t1', usage_hash)
      expect(service.for_thread('t1')[:prompt_tokens]).to eq(100)
    end
  end

  describe '#for_thread' do
    it 'returns empty snapshot for unknown thread' do
      result = service.for_thread('unknown')
      expect(result[:prompt_tokens]).to eq(0)
      expect(result[:turns]).to eq(0)
    end
  end

  describe '#total' do
    it 'sums across all threads' do
      service.record('t1', usage_hash)
      service.record('t2', usage_hash)
      result = service.total
      expect(result[:prompt_tokens]).to eq(200)
      expect(result[:turns]).to eq(2)
      expect(result[:cost_usd]).to eq(0.02)
    end
  end

  describe '#cache_snapshot' do
    it 'returns empty hash for unknown thread' do
      expect(service.cache_snapshot('unknown')).to eq({})
    end
  end

  describe '#reset' do
    it 'clears all data without arguments' do
      service.record('t1', usage_hash)
      service.record('t2', usage_hash)
      service.reset
      expect(service.for_thread('t1')[:prompt_tokens]).to eq(0)
    end

    it 'clears only the specified thread' do
      service.record('t1', usage_hash)
      service.record('t2', usage_hash)
      service.reset('t1')
      expect(service.for_thread('t1')[:prompt_tokens]).to eq(0)
      expect(service.for_thread('t2')[:prompt_tokens]).to eq(100)
    end
  end

  describe '.parse_daily_usage_query' do
    let(:now) { Time.utc(2024, 1, 15, 12, 0, 0) }

    it 'parses explicit from/to dates' do
      result = described_class.parse_daily_usage_query(
        { 'group_by' => 'day', 'from' => '2024-01-01', 'to' => '2024-01-07' }, 'UTC', now
      )
      expect(result[:from]).to eq('2024-01-01')
      expect(result[:to]).to eq('2024-01-07')
      expect(result[:group_by]).to eq('day')
    end

    it 'resolves a week window' do
      result = described_class.parse_daily_usage_query(
        { 'group_by' => 'day', 'window' => 'week' }, 'UTC', now
      )
      expect(result[:from]).to eq('2024-01-09')
      expect(result[:to]).to eq('2024-01-15')
    end

    it 'raises for invalid timezone' do
      expect do
        described_class.parse_daily_usage_query(
          { 'group_by' => 'day', 'from' => '2024-01-01', 'to' => '2024-01-07' }, 'Invalid/Zone'
        )
      end.to raise_error(described_class::UsageValidationError, /invalid timezone/)
    end

    it 'raises for from > to' do
      expect do
        described_class.parse_daily_usage_query(
          { 'group_by' => 'day', 'from' => '2024-01-10', 'to' => '2024-01-01' }, 'UTC'
        )
      end.to raise_error(described_class::UsageValidationError, /from must be on or before to/)
    end

    it 'raises for unsupported group_by' do
      expect do
        described_class.parse_daily_usage_query({ 'group_by' => 'model' }, 'UTC')
      end.to raise_error(described_class::UsageValidationError, /unsupported usage grouping/)
    end
  end

  describe '.parse_model_usage_query' do
    it 'parses model usage with explicit dates' do
      now = Time.utc(2024, 1, 15, 12, 0, 0)
      result = described_class.parse_model_usage_query(
        { 'group_by' => 'model', 'from' => '2024-01-01', 'to' => '2024-01-07' }, 'UTC', now
      )
      expect(result[:group_by]).to eq('model')
    end
  end

  describe '.format_date_in_timezone' do
    it 'formats an ISO timestamp in the given timezone' do
      expect(described_class.format_date_in_timezone('2024-01-15T23:30:00Z', 'Asia/Tokyo')).to eq('2024-01-16')
    end

    it 'returns nil for invalid timezone' do
      expect(described_class.format_date_in_timezone('2024-01-15T12:00:00Z', 'Invalid/Zone')).to be_nil
    end
  end

  describe '.build_thread_usage_response' do
    it 'groups records by thread and sorts by total_tokens' do
      records = [
        { thread_id: 't1', usage: usage_hash.merge(total_tokens: 50) },
        { thread_id: 't2', usage: usage_hash.merge(total_tokens: 200) }
      ]
      result = described_class.build_thread_usage_response(records)
      expect(result[:group_by]).to eq('thread')
      expect(result[:buckets].length).to eq(2)
      expect(result[:buckets].first[:total_tokens]).to be >= result[:buckets].last[:total_tokens]
    end
  end

  describe '.build_daily_usage_response' do
    it 'builds daily buckets for the date range' do
      records = [{ thread_id: 't1', completed_at: '2024-01-02T12:00:00Z', usage: usage_hash }]
      query = { from: '2024-01-01', to: '2024-01-03', timezone: 'UTC' }
      result = described_class.build_daily_usage_response(records, query)
      expect(result[:buckets].length).to eq(3)
      expect(result[:totals][:days]).to eq(3)
    end
  end

  describe '.build_model_usage_response' do
    it 'groups records by model' do
      records = [
        { thread_id: 't1', model: 'gpt-4', completed_at: '2024-01-02T12:00:00Z', usage: usage_hash }
      ]
      query = { from: '2024-01-01', to: '2024-01-03', timezone: 'UTC' }
      result = described_class.build_model_usage_response(records, query)
      expect(result[:group_by]).to eq('model')
      expect(result[:buckets].first[:model]).to eq('gpt-4')
    end
  end
end
