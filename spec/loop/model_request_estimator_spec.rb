# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/model_request_estimator'

RSpec.describe DeepForge::Loop::ModelRequestEstimator do
  describe '.estimate_input_tokens' do
    it 'returns 0 for empty request' do
      expect(described_class.estimate_input_tokens({})).to eq(0)
    end

    it 'estimates system_prompt tokens' do
      request = { system_prompt: 'a' * 40 }
      expect(described_class.estimate_input_tokens(request)).to eq(10)
    end

    it 'estimates mode_instruction tokens' do
      request = { mode_instruction: 'b' * 20 }
      expect(described_class.estimate_input_tokens(request)).to eq(5)
    end

    it 'estimates context_instructions tokens' do
      request = { context_instructions: ['c' * 16, 'd' * 16] }
      # 'c'*16 + "\n" + 'd'*16 = 33 chars, ceil(33/4) = 9
      expect(described_class.estimate_input_tokens(request)).to eq(9)
    end

    it 'estimates tool tokens' do
      request = {
        tools: [{
          name: 'test',
          description: 'g' * 20,
          input_schema: { type: 'object' }
        }]
      }
      expect(described_class.estimate_input_tokens(request)).to be >= 1
    end
  end

  describe '.estimate_items' do
    it 'returns 0 for empty array' do
      expect(described_class.estimate_items([])).to eq(0)
    end
  end

  describe '.estimate_tools' do
    it 'returns 0 for empty tools' do
      expect(described_class.estimate_tools([])).to eq(0)
    end

    it 'estimates tokens for tools' do
      tools = [{ name: 'test', description: 'a' * 20, input_schema: {} }]
      expect(described_class.estimate_tools(tools)).to be >= 1
    end
  end

  describe '.estimate_text' do
    it 'returns 0 for nil' do
      expect(described_class.estimate_text(nil)).to eq(0)
    end

    it 'returns 0 for empty string' do
      expect(described_class.estimate_text('')).to eq(0)
    end

    it 'returns 0 for whitespace-only string' do
      expect(described_class.estimate_text('   ')).to eq(0)
    end

    it 'returns at least 1 token' do
      expect(described_class.estimate_text('a')).to eq(1)
    end

    it 'estimates tokens based on chars_per_token' do
      expect(described_class.estimate_text('a' * 40)).to eq(10)
    end
  end

  describe '.estimate_text_fallbacks' do
    it 'returns 0 for nil' do
      expect(described_class.estimate_text_fallbacks(nil)).to eq(0)
    end

    it 'returns 0 for empty array' do
      expect(described_class.estimate_text_fallbacks([])).to eq(0)
    end

    it 'estimates tokens for fallbacks' do
      fallbacks = [{ name: 'test', mime_type: 'image/png', byte_size: 100, data_base64: 'a' * 40 }]
      expect(described_class.estimate_text_fallbacks(fallbacks)).to be >= 1
    end
  end

  describe '::CHARS_PER_TOKEN' do
    it 'is 4' do
      expect(described_class::CHARS_PER_TOKEN).to eq(4)
    end
  end
end
