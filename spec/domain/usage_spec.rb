# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  describe '.zero_usage' do
    it 'returns a snapshot with all counters at zero' do
      usage = described_class.zero_usage
      expect(usage).to be_a(DeepForge::Contracts::UsageSnapshot)
      expect(usage.prompt_tokens).to eq(0)
      expect(usage.completion_tokens).to eq(0)
      expect(usage.total_tokens).to eq(0)
      expect(usage.cached_tokens).to eq(0)
      expect(usage.cache_hit_tokens).to eq(0)
      expect(usage.cache_miss_tokens).to eq(0)
      expect(usage.cache_hit_rate).to be_nil
      expect(usage.turns).to eq(0)
    end
  end

  describe '.add_usage' do
    it 'sums prompt and completion tokens' do
      a = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 100, completion_tokens: 50, total_tokens: 150,
        cached_tokens: 0, cache_hit_tokens: 0, cache_miss_tokens: 0,
        cache_hit_rate: nil, turns: 1,
        cache_savings_usd: 0, cache_savings_cny: 0,
        token_economy_savings_tokens: 0, token_economy_savings_usd: 0, token_economy_savings_cny: 0
      )
      b = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 200, completion_tokens: 100, total_tokens: 300,
        cached_tokens: 0, cache_hit_tokens: 0, cache_miss_tokens: 0,
        cache_hit_rate: nil, turns: 2,
        cache_savings_usd: 0, cache_savings_cny: 0,
        token_economy_savings_tokens: 0, token_economy_savings_usd: 0, token_economy_savings_cny: 0
      )
      result = described_class.add_usage(a, b)
      expect(result.prompt_tokens).to eq(300)
      expect(result.completion_tokens).to eq(150)
      expect(result.total_tokens).to eq(450)
      expect(result.turns).to eq(3)
    end

    it 'computes cache_hit_rate correctly' do
      a = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
        cached_tokens: 0, cache_hit_tokens: 0, cache_miss_tokens: 0,
        cache_hit_rate: nil, turns: 0,
        cache_savings_usd: 0, cache_savings_cny: 0,
        token_economy_savings_tokens: 0, token_economy_savings_usd: 0, token_economy_savings_cny: 0
      )
      b = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
        cached_tokens: 0, cache_hit_tokens: 30, cache_miss_tokens: 70,
        cache_hit_rate: nil, turns: 0,
        cache_savings_usd: 0, cache_savings_cny: 0,
        token_economy_savings_tokens: 0, token_economy_savings_usd: 0, token_economy_savings_cny: 0
      )
      result = described_class.add_usage(a, b)
      expect(result.cache_hit_rate).to eq(0.3)
    end

    it 'returns nil cache_hit_rate when no cache tokens' do
      a = described_class.zero_usage
      b = described_class.zero_usage
      result = described_class.add_usage(a, b)
      expect(result.cache_hit_rate).to be_nil
    end

    it 'preserves nil costs when both are nil' do
      a = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
        cached_tokens: 0, cache_hit_tokens: 0, cache_miss_tokens: 0,
        cache_hit_rate: nil, turns: 0,
        cost_usd: nil, cost_cny: nil,
        cache_savings_usd: nil, cache_savings_cny: nil,
        token_economy_savings_tokens: 0, token_economy_savings_usd: nil, token_economy_savings_cny: nil
      )
      b = described_class.zero_usage
      result = described_class.add_usage(a, b)
      expect(result.cost_usd).to be_nil
      expect(result.cost_cny).to be_nil
    end

    it 'sums costs when present' do
      a = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
        cached_tokens: 0, cache_hit_tokens: 0, cache_miss_tokens: 0,
        cache_hit_rate: nil, turns: 0,
        cost_usd: 0.05, cost_cny: 0.35,
        cache_savings_usd: 0.01, cache_savings_cny: 0.07,
        token_economy_savings_tokens: 0, token_economy_savings_usd: 0.02, token_economy_savings_cny: 0.14
      )
      b = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
        cached_tokens: 0, cache_hit_tokens: 0, cache_miss_tokens: 0,
        cache_hit_rate: nil, turns: 0,
        cost_usd: 0.03, cost_cny: 0.21,
        cache_savings_usd: 0.01, cache_savings_cny: 0.07,
        token_economy_savings_tokens: 0, token_economy_savings_usd: 0.01, token_economy_savings_cny: 0.07
      )
      result = described_class.add_usage(a, b)
      expect(result.cost_usd).to be_within(0.001).of(0.08)
      expect(result.cost_cny).to be_within(0.001).of(0.56)
      expect(result.cache_savings_usd).to be_within(0.001).of(0.02)
      expect(result.cache_savings_cny).to be_within(0.001).of(0.14)
      expect(result.token_economy_savings_usd).to be_within(0.001).of(0.03)
    end

    it 'sums cached_tokens' do
      a = described_class.zero_usage
      b = DeepForge::Contracts::UsageSnapshot.new(
        prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
        cached_tokens: 50, cache_hit_tokens: 0, cache_miss_tokens: 0,
        cache_hit_rate: nil, turns: 0,
        cache_savings_usd: 0, cache_savings_cny: 0,
        token_economy_savings_tokens: 0, token_economy_savings_usd: 0, token_economy_savings_cny: 0
      )
      result = described_class.add_usage(a, b)
      expect(result.cached_tokens).to eq(50)
    end
  end
end
