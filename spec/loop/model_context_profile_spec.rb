# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/model_context_profile'

RSpec.describe DeepForge::Loop::ModelContextProfile do
  describe '::DEFAULT_CONTEXT_THRESHOLDS' do
    it 'has soft and hard thresholds' do
      expect(described_class::DEFAULT_CONTEXT_THRESHOLDS[:soft_threshold]).to eq(16_000)
      expect(described_class::DEFAULT_CONTEXT_THRESHOLDS[:hard_threshold]).to eq(24_000)
    end
  end

  describe '.normalize_model_id' do
    it 'normalizes and downcases' do
      expect(described_class.normalize_model_id('  DeepSeek-V4-Pro  ')).to eq('deepseek-v4-pro')
    end

    it 'returns empty string for auto' do
      expect(described_class.normalize_model_id('auto')).to eq('')
    end

    it 'returns empty string for nil' do
      expect(described_class.normalize_model_id(nil)).to eq('')
    end
  end

  describe '.model_capabilities' do
    it 'returns auto id for nil' do
      caps = described_class.model_capabilities(nil)
      expect(caps[:id]).to eq('auto')
    end
  end

  describe '.validate_model_context_profile_config' do
    it 'passes for valid profile' do
      expect do
        described_class.validate_model_context_profile_config({
                                                                aliases: ['test'],
                                                                context_window_tokens: 100_000,
                                                                soft_ratio: 0.5,
                                                                hard_ratio: 0.8,
                                                                input_modalities: ['text'],
                                                                output_modalities: ['text'],
                                                                supports_tool_calling: true,
                                                                message_parts: ['text']
                                                              })
      end.not_to raise_error
    end

    it 'raises for invalid aliases' do
      expect do
        described_class.validate_model_context_profile_config({ aliases: 'not array' })
      end.to raise_error(ArgumentError, /aliases/)
    end

    it 'raises for invalid context_window_tokens' do
      expect do
        described_class.validate_model_context_profile_config({ context_window_tokens: -1 })
      end.to raise_error(ArgumentError, /contextWindowTokens/)
    end

    it 'raises for invalid soft_ratio' do
      expect do
        described_class.validate_model_context_profile_config({ soft_ratio: 2.0 })
      end.to raise_error(ArgumentError, /softRatio/)
    end

    it 'raises for invalid hard_ratio' do
      expect do
        described_class.validate_model_context_profile_config({ hard_ratio: -1 })
      end.to raise_error(ArgumentError, /hardRatio/)
    end

    it 'raises for invalid input_modalities' do
      expect do
        described_class.validate_model_context_profile_config({ input_modalities: ['video'] })
      end.to raise_error(ArgumentError, /inputModalities/)
    end

    it 'raises for invalid output_modalities' do
      expect do
        described_class.validate_model_context_profile_config({ output_modalities: ['audio'] })
      end.to raise_error(ArgumentError, /outputModalities/)
    end

    it 'raises for invalid supports_tool_calling' do
      expect do
        described_class.validate_model_context_profile_config({ supports_tool_calling: 'yes' })
      end.to raise_error(ArgumentError, /supportsToolCalling/)
    end

    it 'raises for invalid message_parts' do
      expect do
        described_class.validate_model_context_profile_config({ message_parts: ['video'] })
      end.to raise_error(ArgumentError, /messageParts/)
    end

    it 'raises for invalid context_compaction' do
      expect do
        described_class.validate_model_context_profile_config({ context_compaction: 'bad' })
      end.to raise_error(ArgumentError, /contextCompaction/)
    end

    it 'does nothing for non-Hash input' do
      expect { described_class.validate_model_context_profile_config('not a hash') }.not_to raise_error
    end
  end

  describe '.validate_model_config' do
    it 'passes for valid config' do
      expect do
        described_class.validate_model_config({ profiles: { 'test' => { aliases: ['t'] } } })
      end.not_to raise_error
    end

    it 'raises when profiles is not Hash' do
      expect do
        described_class.validate_model_config({ profiles: 'not hash' })
      end.to raise_error(ArgumentError, /profiles.*Hash/)
    end

    it 'does nothing for nil config' do
      expect { described_class.validate_model_config(nil) }.not_to raise_error
    end
  end

  describe '.from_config' do
    it 'returns default profiles when no config' do
      profiles = described_class.from_config(nil)
      expect(profiles).to be_an(Array)
      expect(profiles.length).to be >= 1
    end

    it 'merges custom profiles' do
      config = {
        profiles: {
          'deepseek-v4-pro' => {
            context_window_tokens: 200_000,
            soft_threshold: 180_000,
            hard_threshold: 190_000
          }
        }
      }
      profiles = described_class.from_config(config)
      pro = profiles.find { |p| p[:canonical_model] == 'deepseek-v4-pro' }
      expect(pro[:context_window_tokens]).to eq(200_000)
    end
  end

  describe '.threshold_from_window' do
    it 'calculates threshold from window and ratio' do
      result = described_class.threshold_from_window(
        context_window_tokens: 100_000,
        ratio: 0.5,
        fallback_ratio: 0.5,
        fallback_threshold: nil
      )
      expect(result).to eq(50_000)
    end

    it 'uses fallback_threshold when no window' do
      result = described_class.threshold_from_window(
        context_window_tokens: nil,
        ratio: 0.5,
        fallback_ratio: 0.5,
        fallback_threshold: 1000
      )
      expect(result).to eq(1000)
    end
  end

  describe '.unique_model_ids' do
    it 'deduplicates and normalizes' do
      result = described_class.unique_model_ids(%w[Pro pro FLASH flash])
      expect(result).to eq(%w[pro flash])
    end

    it 'removes empty strings' do
      result = described_class.unique_model_ids(['auto', '', nil])
      expect(result).to eq([])
    end
  end
end
