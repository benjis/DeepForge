# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/token_economy'

RSpec.describe DeepForge::Loop::TokenEconomy do
  describe '.normalize_config' do
    it 'returns default config when nil' do
      config = described_class.normalize_config(nil)
      expect(config[:enabled]).to be(false)
      expect(config[:compress_tool_descriptions]).to be(true)
      expect(config[:compress_tool_results]).to be(true)
      expect(config[:concise_responses]).to be(true)
    end

    it 'merges with defaults' do
      config = described_class.normalize_config({ enabled: true })
      expect(config[:enabled]).to be(true)
      expect(config[:compress_tool_descriptions]).to be(true)
    end

    it 'merges history_hygiene' do
      config = described_class.normalize_config({
                                                  history_hygiene: { max_tool_result_lines: 100 }
                                                })
      expect(config[:history_hygiene][:max_tool_result_lines]).to eq(100)
    end
  end

  describe '.apply_to_request' do
    it 'returns request unchanged when disabled' do
      request = { history: [], tools: [] }
      config = described_class.normalize_config(nil)
      result = described_class.apply_to_request(request, config)
      expect(result).to equal(request)
    end

    it 'adds concise instruction when enabled' do
      request = { context_instructions: [], tools: [], history: [] }
      config = described_class.normalize_config({ enabled: true })
      result = described_class.apply_to_request(request, config)
      expect(result[:context_instructions]).to include(described_class::TOKEN_ECONOMY_INSTRUCTION)
    end

    it 'compresses tool descriptions when enabled' do
      tool = { name: 'test', description: 'Please kindly test this', input_schema: {} }
      request = { tools: [tool], history: [] }
      config = described_class.normalize_config({ enabled: true })
      result = described_class.apply_to_request(request, config)
      expect(result[:tools].first[:description]).not_to include('Please')
    end

    it 'compresses tool results when enabled' do
      item = { kind: 'tool_result', tool_name: 'bash', output: 'a' * 1000 }
      request = { tools: [], history: [item] }
      config = described_class.normalize_config({ enabled: true })
      result = described_class.apply_to_request(request, config)
      expect(result[:history].first[:output]).to be_a(String)
    end
  end

  describe '.compress_prose' do
    it 'removes filler words' do
      result = described_class.compress_prose('This is just a really actually test')
      expect(result).not_to include('just')
      expect(result).not_to include('really')
      expect(result).not_to include('actually')
    end

    it 'removes pleasantries' do
      result = described_class.compress_prose('Please, thank you for your help.')
      expect(result).not_to include('Please')
      expect(result).not_to include('thank you')
    end

    it 'removes hedging' do
      result = described_class.compress_prose('Perhaps maybe it could work')
      expect(result).not_to include('Perhaps')
      expect(result).not_to include('maybe')
    end

    it 'preserves protected segments' do
      result = described_class.compress_prose('Use `puts "hello"` please')
      expect(result).to include('puts "hello"')
    end

    it 'preserves URLs' do
      result = described_class.compress_prose('Visit https://example.com please')
      expect(result).to include('https://example.com')
    end

    it 'returns empty string for blank input' do
      expect(described_class.compress_prose('')).to eq('')
      expect(described_class.compress_prose('  ')).to eq('  ')
    end
  end

  describe '.compact_line' do
    it 'returns short lines unchanged' do
      expect(described_class.compact_line('hello')).to eq('hello')
    end

    it 'truncates long lines with ellipsis' do
      long_line = 'a' * 300
      result = described_class.compact_line(long_line)
      expect(result.length).to be <= described_class::MAX_LINE_CHARS + 5
      expect(result).to include('...')
    end
  end

  describe '.normalize_text_block' do
    it 'removes duplicate lines' do
      text = "line1\nline1\nline2"
      result = described_class.normalize_text_block(text)
      expect(result).to include('line1')
      expect(result).to include('repeated')
    end

    it 'limits blank runs to 2' do
      text = "a\n\n\n\n\nb"
      result = described_class.normalize_text_block(text)
      blank_count = result.split("\n").count { |l| l.strip.empty? }
      expect(blank_count).to be <= 2
    end

    it 'handles CRLF' do
      text = "a\r\nb"
      result = described_class.normalize_text_block(text)
      expect(result).to include('a')
      expect(result).to include('b')
    end
  end

  describe '.split_lines' do
    it 'splits text into lines' do
      expect(described_class.split_lines("a\nb\nc")).to eq(%w[a b c])
    end

    it 'returns empty array for nil' do
      expect(described_class.split_lines(nil)).to eq([])
    end

    it 'returns empty array for empty string' do
      expect(described_class.split_lines('')).to eq([])
    end
  end

  describe '.fits_text_budget?' do
    it 'returns true when within budget' do
      expect(described_class.fits_text_budget?("a\nb", 5, 1024)).to be(true)
    end

    it 'returns false when exceeding line budget' do
      expect(described_class.fits_text_budget?("a\nb\nc", 2, 1024)).to be(false)
    end

    it 'returns false when exceeding byte budget' do
      expect(described_class.fits_text_budget?('a' * 100, 10, 10)).to be(false)
    end
  end

  describe '.fit_lines_to_budget' do
    it 'returns lines within budget' do
      lines = %w[a b c]
      result = described_class.fit_lines_to_budget(lines, 2, 1024)
      expect(result.length).to eq(2)
    end

    it 'stops at byte budget' do
      lines = ['a' * 10, 'b' * 10]
      result = described_class.fit_lines_to_budget(lines, 100, 15)
      expect(result.length).to eq(1)
    end
  end

  describe '.compact_tool_output' do
    it 'compacts bash output' do
      output = { output: 'a' * 1000 }
      result = described_class.compact_tool_output('bash', output)
      expect(result[:output]).to be_a(String)
    end

    it 'compacts read output' do
      output = { content: 'a' * 1000 }
      result = described_class.compact_tool_output('read', output)
      expect(result[:content]).to be_a(String)
    end

    it 'compacts grep output' do
      output = { matches: (1..100).map { |i| { text: "match#{i}" } } }
      result = described_class.compact_tool_output('grep', output)
      expect(result[:matches].length).to eq(described_class::MAX_GREP_MATCHES)
    end

    it 'compacts find output' do
      output = { matches: (1..200).map { |i| "file#{i}" } }
      result = described_class.compact_tool_output('find', output)
      expect(result[:matches].length).to eq(described_class::MAX_FIND_MATCHES)
    end

    it 'compacts ls output' do
      output = { entries: (1..200).map { |i| "entry#{i}" }, names: (1..200).map { |i| "name#{i}" } }
      result = described_class.compact_tool_output('ls', output)
      expect(result[:entries].length).to eq(described_class::MAX_LS_ENTRIES)
    end

    it 'compacts string output generically' do
      result = described_class.compact_tool_output('unknown', 'hello world')
      expect(result).to be_a(String)
    end

    it 'returns hash output unchanged for unknown tool' do
      output = { key: 'value' }
      result = described_class.compact_tool_output('unknown', output)
      expect(result).to eq(output)
    end
  end

  describe '.compact_history_item' do
    it 'compresses tool_call summary' do
      item = { kind: 'tool_call', summary: 'Please read the file kindly' }
      result = described_class.compact_history_item(item)
      expect(result[:summary]).not_to include('Please')
    end

    it 'compacts tool_result output' do
      item = { kind: 'tool_result', tool_name: 'bash', output: 'a' * 1000 }
      result = described_class.compact_history_item(item)
      expect(result[:output]).to be_a(String)
    end

    it 'returns non-tool items unchanged' do
      item = { kind: 'user_message', text: 'hello' }
      result = described_class.compact_history_item(item)
      expect(result).to equal(item)
    end
  end

  describe '.compact_tool_spec' do
    it 'compresses tool description' do
      tool = { name: 'test', description: 'Please kindly test this', input_schema: {} }
      result = described_class.compact_tool_spec(tool)
      expect(result[:description]).not_to include('Please')
    end

    it 'compacts schema descriptions' do
      schema = { 'properties' => { 'name' => { 'description' => 'Please enter a name' } } }
      tool = { name: 'test', description: 'test', input_schema: schema }
      result = described_class.compact_tool_spec(tool)
      expect(result[:input_schema]['properties']['name']['description']).not_to include('Please')
    end
  end

  describe '.compact_schema_descriptions' do
    it 'compresses description strings in schemas' do
      schema = { 'type' => 'object', 'description' => 'Please enter a value' }
      result = described_class.compact_schema_descriptions(schema)
      expect(result['description']).not_to include('Please')
    end

    it 'handles nested schemas' do
      schema = { 'properties' => { 'name' => { 'description' => 'Please enter name' } } }
      result = described_class.compact_schema_descriptions(schema)
      expect(result['properties']['name']['description']).not_to include('Please')
    end

    it 'handles arrays' do
      schema = [{ 'description' => 'Please test' }]
      result = described_class.compact_schema_descriptions(schema)
      expect(result[0]['description']).not_to include('Please')
    end
  end

  describe '.with_protected_segments' do
    it 'protects code blocks from modification' do
      result = described_class.with_protected_segments('Use `puts` please') do |text|
        text.gsub('please', 'REMOVED')
      end
      expect(result).to include('puts')
    end

    it 'restores protected segments after processing' do
      result = described_class.with_protected_segments('test `code` here') do |text|
        text.gsub('test', 'MODIFIED')
      end
      expect(result).to include('MODIFIED')
      expect(result).to include('code')
    end
  end

  describe 'TOKEN_ECONOMY_INSTRUCTION' do
    it 'is a non-empty string' do
      expect(described_class::TOKEN_ECONOMY_INSTRUCTION).to be_a(String)
      expect(described_class::TOKEN_ECONOMY_INSTRUCTION).not_to be_empty
    end
  end
end
