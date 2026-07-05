# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Telemetry::UsageCounter do
  subject(:counter) { described_class.new }

  let(:snapshot) do
    DeepForge::Contracts::UsageSnapshot.new(
      prompt_tokens: 100, completion_tokens: 50, total_tokens: 150,
      cached_tokens: 20, cache_hit_tokens: 15, cache_miss_tokens: 5,
      cache_hit_rate: nil, turns: 1, cost_usd: 0.01, cost_cny: 0.07,
      cache_savings_usd: 0.001, cache_savings_cny: 0.007,
      token_economy_savings_tokens: 10, token_economy_savings_usd: 0.002, token_economy_savings_cny: 0.014
    )
  end

  describe '#seed' do
    it 'stores a normalized snapshot' do
      result = counter.seed('t1', snapshot)
      expect(result.prompt_tokens).to eq(100)
      expect(result.turns).to eq(1)
    end

    it 'clamps negative values to zero' do
      bad = DeepForge::Contracts::UsageSnapshot.new(prompt_tokens: -5, completion_tokens: -3, total_tokens: 0, turns: 0)
      result = counter.seed('t1', bad)
      expect(result.prompt_tokens).to eq(0)
      expect(result.completion_tokens).to eq(0)
    end
  end

  describe '#record' do
    it 'accumulates tokens across multiple records' do
      counter.record('t1', snapshot)
      counter.record('t1', snapshot)
      result = counter.for_thread('t1')
      expect(result.prompt_tokens).to eq(200)
      expect(result.completion_tokens).to eq(100)
      expect(result.total_tokens).to eq(300)
    end

    it 'increments turns' do
      counter.record('t1', snapshot)
      counter.record('t1', snapshot)
      expect(counter.for_thread('t1').turns).to eq(2)
    end

    it 'defaults to 1 turn when zero' do
      zero = DeepForge::Contracts::UsageSnapshot.new(prompt_tokens: 10, completion_tokens: 5, total_tokens: 15,
                                                     turns: 0)
      counter.record('t1', zero)
      expect(counter.for_thread('t1').turns).to eq(1)
    end

    it 'computes cache_hit_rate' do
      counter.record('t1', snapshot)
      expect(counter.for_thread('t1').cache_hit_rate).to eq(0.75)
    end

    it 'returns nil cache_hit_rate without cache data' do
      counter.record('t1',
                     DeepForge::Contracts::UsageSnapshot.new(prompt_tokens: 10, completion_tokens: 5, total_tokens: 15,
                                                             turns: 1))
      expect(counter.for_thread('t1').cache_hit_rate).to be_nil
    end

    it 'merges cost_usd additively' do
      counter.record('t1', snapshot)
      counter.record('t1', snapshot)
      expect(counter.for_thread('t1').cost_usd).to eq(0.02)
    end

    it 'handles nil costs' do
      counter.record('t1',
                     DeepForge::Contracts::UsageSnapshot.new(prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, turns: 1,
                                                             cost_usd: nil))
      expect(counter.for_thread('t1').cost_usd).to be_nil
    end

    it 'combines nil and non-nil cost' do
      counter.record('t1', snapshot)
      counter.record('t1',
                     DeepForge::Contracts::UsageSnapshot.new(prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, turns: 1,
                                                             cost_usd: nil))
      expect(counter.for_thread('t1').cost_usd).to eq(0.01)
    end

    it 'accumulates token economy savings' do
      counter.record('t1', snapshot)
      counter.record('t1', snapshot)
      expect(counter.for_thread('t1').token_economy_savings_tokens).to eq(20)
    end

    it 'propagates has_error' do
      counter.record('t1',
                     DeepForge::Contracts::UsageSnapshot.new(prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, turns: 1,
                                                             has_error: true))
      expect(counter.for_thread('t1').has_error).to be true
    end
  end

  describe '#record_token_economy_savings' do
    it 'accumulates savings' do
      counter.seed('t1', snapshot)
      counter.record_token_economy_savings('t1', token_economy_savings_tokens: 50, token_economy_savings_usd: 0.05)
      expect(counter.for_thread('t1').token_economy_savings_tokens).to eq(60)
      expect(counter.for_thread('t1').token_economy_savings_usd).to be_within(0.0001).of(0.052)
    end

    it 'handles missing thread' do
      counter.record_token_economy_savings('new', token_economy_savings_tokens: 10)
      expect(counter.for_thread('new').token_economy_savings_tokens).to eq(10)
    end
  end

  describe '#total' do
    it 'returns zeros for empty counter' do
      expect(counter.total.prompt_tokens).to eq(0)
    end

    it 'sums across all threads' do
      counter.record('t1', snapshot)
      counter.record('t2', snapshot)
      result = counter.total
      expect(result.prompt_tokens).to eq(200)
      expect(result.turns).to eq(2)
    end
  end

  describe '#for_thread' do
    it 'returns empty snapshot for unknown thread' do
      expect(counter.for_thread('unknown').prompt_tokens).to eq(0)
    end
  end

  describe '#reset' do
    it 'clears all data without arguments' do
      counter.record('t1', snapshot)
      counter.reset
      expect(counter.for_thread('t1').prompt_tokens).to eq(0)
    end

    it 'clears only the specified thread' do
      counter.record('t1', snapshot)
      counter.record('t2', snapshot)
      counter.reset('t1')
      expect(counter.for_thread('t1').prompt_tokens).to eq(0)
      expect(counter.for_thread('t2').prompt_tokens).to eq(100)
    end
  end
end
