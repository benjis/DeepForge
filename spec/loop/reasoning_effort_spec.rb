# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/reasoning_effort'

RSpec.describe DeepForge::Loop::ModelReasoningEffort do
  describe '::OFF' do
    it 'is "off"' do
      expect(described_class::OFF).to eq('off')
    end
  end

  describe '::HIGH' do
    it 'is "high"' do
      expect(described_class::HIGH).to eq('high')
    end
  end

  describe '::MAX' do
    it 'is "max"' do
      expect(described_class::MAX).to eq('max')
    end
  end

  describe '::VALUES' do
    it 'contains all three levels' do
      expect(described_class::VALUES).to contain_exactly('off', 'high', 'max')
    end

    it 'is frozen' do
      expect(described_class::VALUES).to be_frozen
    end
  end

  describe '.safe_parse' do
    it 'parses "off"' do
      expect(described_class.safe_parse('off')).to eq('off')
    end

    it 'parses "high"' do
      expect(described_class.safe_parse('high')).to eq('high')
    end

    it 'parses "max"' do
      expect(described_class.safe_parse('max')).to eq('max')
    end

    it 'strips whitespace' do
      expect(described_class.safe_parse('  high  ')).to eq('high')
    end

    it 'returns nil for invalid value' do
      expect(described_class.safe_parse('invalid')).to be_nil
    end

    it 'returns nil for non-string' do
      expect(described_class.safe_parse(nil)).to be_nil
      expect(described_class.safe_parse(123)).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.safe_parse('')).to be_nil
    end
  end
end

RSpec.describe 'normalize_role_reasoning_effort' do
  it 'returns parsed value for valid input' do
    expect(normalize_role_reasoning_effort('high')).to eq('high')
  end

  it 'returns off for nil' do
    expect(normalize_role_reasoning_effort(nil)).to eq('off')
  end

  it 'returns off for invalid string' do
    expect(normalize_role_reasoning_effort('invalid')).to eq('off')
  end

  it 'strips whitespace from input' do
    expect(normalize_role_reasoning_effort('  max  ')).to eq('max')
  end

  it 'returns off for non-string input' do
    expect(normalize_role_reasoning_effort(123)).to eq('off')
  end
end
