# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe '.empty_usage_snapshot' do
    subject(:usage) { described_class.empty_usage_snapshot }

    it 'returns a UsageSnapshot with zero counters' do
      expect(usage).to be_a(described_class::UsageSnapshot)
      expect(usage.prompt_tokens).to eq(0)
      expect(usage.completion_tokens).to eq(0)
      expect(usage.total_tokens).to eq(0)
      expect(usage.cached_tokens).to eq(0)
      expect(usage.cache_hit_tokens).to eq(0)
      expect(usage.cache_miss_tokens).to eq(0)
      expect(usage.cache_hit_rate).to be_nil
      expect(usage.turns).to eq(0)
    end

    it 'has nil cost fields (not set in empty snapshot)' do
      expect(usage.cost_usd).to be_nil
      expect(usage.cost_cny).to be_nil
    end

    it 'has zero savings fields' do
      expect(usage.cache_savings_usd).to eq(0)
      expect(usage.cache_savings_cny).to eq(0)
      expect(usage.token_economy_savings_tokens).to eq(0)
      expect(usage.token_economy_savings_usd).to eq(0)
      expect(usage.token_economy_savings_cny).to eq(0)
    end
  end

  describe 'UsageSnapshot struct' do
    it 'supports has_error field' do
      usage = described_class::UsageSnapshot.new(
        prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
        has_error: true
      )
      expect(usage.has_error).to be(true)
    end
  end

  describe 'DailyUsageBucket' do
    it 'creates with keyword init' do
      bucket = described_class::DailyUsageBucket.new(
        date: '2025-01-01', input_tokens: 100, output_tokens: 50
      )
      expect(bucket.date).to eq('2025-01-01')
    end
  end

  describe 'ThreadUsageBucket' do
    it 'creates with keyword init' do
      bucket = described_class::ThreadUsageBucket.new(thread_id: 't1', input_tokens: 100)
      expect(bucket.thread_id).to eq('t1')
    end
  end

  describe 'ModelUsageBucket' do
    it 'creates with keyword init' do
      bucket = described_class::ModelUsageBucket.new(model: 'deepseek-chat', input_tokens: 200)
      expect(bucket.model).to eq('deepseek-chat')
    end
  end
end
