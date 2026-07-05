# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/model/deepseek_pricing'

RSpec.describe DeepForge::Adapters::Model::DeepseekPricing do
  describe '.pricing_tier_for_model' do
    it 'returns :flash for deepseek-chat' do
      expect(described_class.pricing_tier_for_model('deepseek-chat')).to eq(:flash)
    end

    it 'returns :flash for deepseek-reasoner' do
      expect(described_class.pricing_tier_for_model('deepseek-reasoner')).to eq(:flash)
    end

    it 'returns :flash for deepseek-v4-flash' do
      expect(described_class.pricing_tier_for_model('deepseek-v4-flash')).to eq(:flash)
    end

    it 'returns :flash for provider-prefixed flash models' do
      expect(described_class.pricing_tier_for_model('openrouter/deepseek-v4-flash')).to eq(:flash)
    end

    it 'returns :pro for deepseek-v4-pro' do
      expect(described_class.pricing_tier_for_model('deepseek-v4-pro')).to eq(:pro)
    end

    it 'returns :pro for provider-prefixed pro models' do
      expect(described_class.pricing_tier_for_model('openrouter/deepseek-v4-pro')).to eq(:pro)
    end

    it 'returns nil for unknown model' do
      expect(described_class.pricing_tier_for_model('gpt-4')).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.pricing_tier_for_model('')).to be_nil
    end

    it 'is case-insensitive' do
      expect(described_class.pricing_tier_for_model('DeepSeek-Chat')).to eq(:flash)
    end
  end

  describe '.compute_cost' do
    let(:prices) { { input_cache_hit: 0.0028, input_cache_miss: 0.14, output: 0.28 } }

    it 'computes cost with all token types' do
      cost = described_class.compute_cost(prices, 1_000_000, 1_000_000, 1_000_000)
      expect(cost).to be_within(0.001).of(0.4228)
    end

    it 'computes cost with zero tokens' do
      expect(described_class.compute_cost(prices, 0, 0, 0)).to eq(0.0)
    end

    it 'computes cost with only output tokens' do
      cost = described_class.compute_cost(prices, 0, 0, 1_000_000)
      expect(cost).to eq(0.28)
    end
  end

  describe '.estimate_deepseek_cost' do
    it 'returns cost_usd and cost_cny for known models' do
      result = described_class.estimate_deepseek_cost(
        model: 'deepseek-chat',
        cache_hit_tokens: 1000,
        cache_miss_tokens: 1000,
        output_tokens: 1000
      )
      expect(result).to have_key(:cost_usd)
      expect(result).to have_key(:cost_cny)
      expect(result[:cost_usd]).to be > 0
    end

    it 'returns nil for unknown model' do
      result = described_class.estimate_deepseek_cost(
        model: 'gpt-4',
        cache_hit_tokens: 1000,
        cache_miss_tokens: 1000,
        output_tokens: 1000
      )
      expect(result).to be_nil
    end
  end

  describe '.estimate_deepseek_input_token_cost' do
    it 'treats all tokens as cache misses' do
      result = described_class.estimate_deepseek_input_token_cost(
        model: 'deepseek-chat',
        input_tokens: 1_000_000
      )
      expect(result[:cost_usd]).to be_within(0.001).of(0.14)
    end
  end

  describe '.estimate_deepseek_cache_savings' do
    it 'computes savings from cache hits' do
      result = described_class.estimate_deepseek_cache_savings(
        model: 'deepseek-chat',
        cache_hit_tokens: 1_000_000
      )
      expect(result[:cost_usd]).to be > 0
      expect(result[:cost_cny]).to be > 0
    end

    it 'returns nil for unknown model' do
      result = described_class.estimate_deepseek_cache_savings(
        model: 'unknown',
        cache_hit_tokens: 1000
      )
      expect(result).to be_nil
    end
  end
end
