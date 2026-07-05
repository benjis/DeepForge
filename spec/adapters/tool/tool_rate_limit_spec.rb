# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/tool_rate_limit'

RSpec.describe DeepForge::Adapters::Tool::ToolRateLimit do
  describe '.parse_rate_limited_tool_result' do
    it 'returns nil for non-rate-limited output' do
      result = described_class.parse_rate_limited_tool_result({ output: 'success' })
      expect(result).to be_nil
    end

    it 'returns nil for nil output' do
      result = described_class.parse_rate_limited_tool_result(nil)
      expect(result).to be_nil
    end

    it 'returns nil for empty string' do
      result = described_class.parse_rate_limited_tool_result('')
      expect(result).to be_nil
    end

    it 'detects rate limit in string output' do
      result = described_class.parse_rate_limited_tool_result('rate limited: too many requests')
      expect(result).not_to be_nil
      expect(result.rate_limited).to be true
      expect(result.message).to include('rate limited')
    end

    it 'detects "429" in output' do
      result = described_class.parse_rate_limited_tool_result('status: 429')
      expect(result).not_to be_nil
      expect(result.rate_limited).to be true
    end

    it 'detects "quota exceeded" in output' do
      result = described_class.parse_rate_limited_tool_result('quota exceeded')
      expect(result).not_to be_nil
      expect(result.rate_limited).to be true
    end

    it 'parses retry-after seconds' do
      result = described_class.parse_rate_limited_tool_result('rate limited, retry after 30 seconds')
      expect(result).not_to be_nil
      expect(result.retry_after_seconds).to eq(30.0)
    end

    it 'parses retry-after in minutes' do
      result = described_class.parse_rate_limited_tool_result('rate limited, retry after 2 minutes')
      expect(result).not_to be_nil
      expect(result.retry_after_seconds).to eq(120.0)
    end

    it 'parses retry-after in milliseconds' do
      result = described_class.parse_rate_limited_tool_result('rate limited, try again in 500ms')
      expect(result).not_to be_nil
      expect(result.retry_after_seconds).to eq(1.0)
    end

    it 'detects rate limit in hash output' do
      result = described_class.parse_rate_limited_tool_result({ error: 'rate limit exceeded' })
      expect(result).not_to be_nil
      expect(result.rate_limited).to be true
    end

    it 'detects rate limit in nested array output' do
      result = described_class.parse_rate_limited_tool_result(['too many requests'])
      expect(result).not_to be_nil
      expect(result.rate_limited).to be true
    end
  end

  describe '.normalize_rate_limited_tool_output' do
    it 'returns original output when not rate limited' do
      output = { data: 'success' }
      result = described_class.normalize_rate_limited_tool_output(output)
      expect(result[:output]).to eq(output)
      expect(result[:rate_limited]).to be false
    end

    it 'normalizes rate limited output' do
      result = described_class.normalize_rate_limited_tool_output('rate limited: wait 10s')
      expect(result[:rate_limited]).to be true
      expect(result[:is_error]).to be true
      expect(result[:output][:code]).to eq('rate_limited')
      expect(result[:output][:rate_limited]).to be true
      expect(result[:output][:original]).to eq('rate limited: wait 10s')
    end

    it 'includes retry_after_seconds when available' do
      result = described_class.normalize_rate_limited_tool_output('rate limited, retry after 5 seconds')
      expect(result[:output][:retry_after_seconds]).to eq(5.0)
    end
  end
end
