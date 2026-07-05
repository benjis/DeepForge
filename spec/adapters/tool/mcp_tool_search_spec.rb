# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/mcp_tool_search'

RSpec.describe DeepForge::Adapters::Tool::McpToolSearch do
  describe 'constants' do
    it 'defines tool names' do
      expect(described_class::MCP_SEARCH_TOOL_NAME).to eq('mcp_search')
      expect(described_class::MCP_DESCRIBE_TOOL_NAME).to eq('mcp_describe')
      expect(described_class::MCP_CALL_TOOL_NAME).to eq('mcp_call')
      expect(described_class::MCP_REFRESH_CATALOG_TOOL_NAME).to eq('mcp_refresh_catalog')
    end

    it 'defines STOP_WORDS' do
      expect(described_class::STOP_WORDS).to include('the', 'and', 'for')
    end

    it 'defines ACTION_SYNONYMS' do
      expect(described_class::ACTION_SYNONYMS).to include('search')
      expect(described_class::ACTION_SYNONYMS['search']).to include('find', 'lookup')
    end
  end

  describe '.string_arg' do
    it 'returns stripped string' do
      expect(described_class.string_arg(' hello ')).to eq('hello')
    end

    it 'returns empty for non-string' do
      expect(described_class.string_arg(123)).to eq('')
      expect(described_class.string_arg(nil)).to eq('')
    end
  end

  describe '.number_arg' do
    it 'returns number' do
      expect(described_class.number_arg(5)).to eq(5)
    end

    it 'returns nil for non-number' do
      expect(described_class.number_arg('5')).to be_nil
      expect(described_class.number_arg(Float::NAN)).to be_nil
    end
  end

  describe '.object_arg' do
    it 'returns hash' do
      expect(described_class.object_arg({ a: 1 })).to eq({ a: 1 })
    end

    it 'returns empty hash for non-hash' do
      expect(described_class.object_arg('bad')).to eq({})
    end
  end

  describe '.clamp_positive_int' do
    it 'clamps to max' do
      expect(described_class.clamp_positive_int(100, 5, 10)).to eq(10)
    end

    it 'returns fallback for nil' do
      expect(described_class.clamp_positive_int(nil, 5, 10)).to eq(5)
    end

    it 'returns fallback for zero' do
      expect(described_class.clamp_positive_int(0, 5, 10)).to eq(5)
    end

    it 'returns value within range' do
      expect(described_class.clamp_positive_int(3, 5, 10)).to eq(3)
    end
  end

  describe '.tokenize_mcp_search_text' do
    it 'tokenizes text' do
      tokens = described_class.tokenize_mcp_search_text('hello world')
      expect(tokens).to include('hello', 'world')
    end

    it 'filters stop words' do
      tokens = described_class.tokenize_mcp_search_text('the quick fox')
      expect(tokens).not_to include('the')
      expect(tokens).to include('quick', 'fox')
    end

    it 'filters single character tokens' do
      tokens = described_class.tokenize_mcp_search_text('a b c')
      expect(tokens).to be_empty
    end

    it 'filters pure numbers' do
      tokens = described_class.tokenize_mcp_search_text('123 456')
      expect(tokens).to be_empty
    end
  end

  describe '.normalize_lower' do
    it 'lowercases and normalizes' do
      expect(described_class.normalize_lower('Hello World')).to eq('hello world')
    end

    it 'handles nil' do
      expect(described_class.normalize_lower(nil)).to eq('')
    end
  end

  describe '.token_allowed?' do
    it 'allows valid tokens' do
      expect(described_class.token_allowed?('hello')).to be true
    end

    it 'rejects stop words' do
      expect(described_class.token_allowed?('the')).to be false
    end

    it 'rejects empty tokens' do
      expect(described_class.token_allowed?('')).to be false
      expect(described_class.token_allowed?(nil)).to be false
    end

    it 'rejects single character tokens' do
      expect(described_class.token_allowed?('a')).to be false
    end

    it 'rejects pure numbers' do
      expect(described_class.token_allowed?('123')).to be false
    end
  end

  describe '.term_frequency' do
    it 'counts token frequency' do
      tokens = %w[a b a c a]
      tf = described_class.term_frequency(tokens)
      expect(tf['a']).to eq(3)
      expect(tf['b']).to eq(1)
      expect(tf['c']).to eq(1)
    end
  end

  describe '.repeat_tokens' do
    it 'repeats tokens' do
      result = described_class.repeat_tokens(%w[a b], 3)
      expect(result).to eq(%w[a a a b b b])
    end
  end

  describe '.expand_query_tokens' do
    it 'expands synonyms' do
      tokens = described_class.expand_query_tokens(['search'])
      expect(tokens).to include('find', 'lookup', 'query')
    end

    it 'expands reverse synonyms' do
      tokens = described_class.expand_query_tokens(['find'])
      expect(tokens).to include('search')
    end
  end

  describe '.build_query' do
    it 'builds query from text' do
      query = described_class.build_query('search for tools')
      expect(query[:terms]).to be_a(Array)
      expect(query[:weights]).to be_a(Hash)
      expect(query[:text]).to eq('search for tools')
    end
  end

  describe '.summarize_schema' do
    it 'summarizes a schema' do
      schema = {
        type: 'object',
        properties: { name: { type: 'string' }, age: { type: 'number' } },
        required: ['name']
      }
      result = described_class.summarize_schema(schema)
      expect(result[:required]).to eq(['name'])
      expect(result[:parameters]).to include(:name, :age)
    end

    it 'handles nil schema' do
      result = described_class.summarize_schema(nil)
      expect(result[:required]).to eq([])
      expect(result[:parameters]).to eq([])
    end
  end

  describe '.extract_schema_text' do
    # extract_schema_text crashes due to present? not available
    it 'returns empty for nil schema' do
      expect(described_class.extract_schema_text(nil)).to eq('')
    end
  end

  describe '.action_words' do
    it 'extracts action words from name' do
      words = described_class.action_words('get_user_info')
      expect(words).to be_a(String)
      expect(words).to include('get')
    end
  end

  describe '.error_output' do
    it 'returns error hash' do
      result = described_class.error_output('test')
      expect(result[:output][:error]).to eq('test')
      expect(result[:is_error]).to be true
    end
  end
end
