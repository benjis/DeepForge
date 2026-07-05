# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/request_history_hygiene'

RSpec.describe DeepForge::Loop::RequestHistoryHygiene do
  describe '.apply' do
    it 'returns items unchanged when no tool results' do
      items = [
        { kind: 'user_message', text: 'hi' },
        { kind: 'assistant_text', text: 'hello' }
      ]
      result = described_class.apply(items)
      expect(result).to equal(items)
    end

    it 'compacts large tool results' do
      items = [
        { kind: 'tool_result', call_id: 'c1', tool_name: 'bash', output: 'a' * 100_000 }
      ]
      result = described_class.apply(items, { max_tool_result_bytes: 1000 })
      expect(result.first[:output]).to include('cache hygiene')
    end

    it 'compacts completed tool call arguments' do
      items = [
        { kind: 'tool_call', call_id: 'c1', tool_name: 'read', arguments: { path: 'a' * 10_000 } },
        { kind: 'tool_result', call_id: 'c1', tool_name: 'read', output: 'result' }
      ]
      result = described_class.apply(items, { max_tool_argument_string_bytes: 100 })
      expect(result.first[:arguments][:path]).to include('cache hygiene')
    end

    it 'does not compact tool calls without matching result' do
      args = { path: 'a' * 10_000 }
      items = [
        { kind: 'tool_call', call_id: 'c1', tool_name: 'read', arguments: args.dup }
      ]
      result = described_class.apply(items, { max_tool_argument_string_bytes: 100 })
      expect(result.first[:arguments][:path]).to eq(args[:path])
    end
  end

  describe '.normalize_options' do
    it 'returns defaults for empty options' do
      opts = described_class.normalize_options({})
      expect(opts[:max_tool_result_lines]).to eq(described_class::DEFAULT_MAX_TOOL_RESULT_LINES)
      expect(opts[:max_tool_result_bytes]).to eq(described_class::DEFAULT_MAX_TOOL_RESULT_BYTES)
    end

    it 'overrides provided options' do
      opts = described_class.normalize_options({ max_tool_result_lines: 10 })
      expect(opts[:max_tool_result_lines]).to eq(10)
    end

    it 'enforces minimum values' do
      opts = described_class.normalize_options({
                                                 max_tool_result_lines: 0,
                                                 max_tool_result_bytes: 0,
                                                 max_tool_result_tokens: 0,
                                                 max_tool_argument_string_bytes: 0,
                                                 max_tool_argument_string_tokens: 0,
                                                 max_array_items: 0
                                               })
      expect(opts[:max_tool_result_lines]).to eq(1)
      expect(opts[:max_tool_result_bytes]).to eq(512)
      expect(opts[:max_tool_result_tokens]).to eq(128)
      expect(opts[:max_tool_argument_string_bytes]).to eq(512)
      expect(opts[:max_tool_argument_string_tokens]).to eq(128)
      expect(opts[:max_array_items]).to eq(1)
    end
  end

  describe '.compact_tool_result_output' do
    it 'returns unchanged for small text' do
      result = described_class.compact_tool_result_output('hello', described_class.normalize_options({}))
      expect(result[:changed]).to be(false)
    end

    it 'compacts large text' do
      large = 'a' * 100_000
      result = described_class.compact_tool_result_output(large, {
                                                            max_tool_result_bytes: 1000,
                                                            max_tool_result_lines: 10,
                                                            max_tool_result_tokens: 100
                                                          })
      expect(result[:changed]).to be(true)
    end

    it 'handles hash output' do
      output = { content: 'hello', extra: 'world' }
      result = described_class.compact_tool_result_output(output, described_class.normalize_options({}))
      expect(result[:changed]).to be(false)
    end

    it 'handles array output' do
      output = (1..100).to_a
      result = described_class.compact_tool_result_output(output, {
                                                            max_array_items: 10
                                                          })
      expect(result[:changed]).to be(true)
    end
  end

  describe '.compact_tool_result_text' do
    it 'returns unchanged for small text' do
      result = described_class.compact_tool_result_text('hello', described_class.normalize_options({}))
      expect(result[:changed]).to be(false)
    end

    it 'compacts text exceeding limits' do
      large = ("line\n" * 500)
      result = described_class.compact_tool_result_text(large, {
                                                          max_tool_result_lines: 10,
                                                          max_tool_result_bytes: 1000,
                                                          max_tool_result_tokens: 100
                                                        })
      expect(result[:changed]).to be(true)
      expect(result[:value]).to include('cache hygiene')
    end
  end

  describe '.select_cache_useful_lines' do
    it 'returns all lines when within limit' do
      lines = %w[a b c]
      expect(described_class.select_cache_useful_lines(lines, 10)).to eq(lines)
    end

    it 'selects head, tail, and signal lines' do
      lines = Array.new(100) { |i| "line#{i}" }
      lines[50] = 'error: something failed'
      result = described_class.select_cache_useful_lines(lines, 50)
      expect(result.length).to be <= 50
      expect(result).to include('error: something failed')
    end
  end

  describe '.compact_line' do
    it 'returns short lines unchanged' do
      expect(described_class.compact_line('hello')).to eq('hello')
    end

    it 'truncates long lines' do
      long = 'a' * 300
      result = described_class.compact_line(long)
      expect(result.length).to be <= described_class::MAX_LINE_CHARS + 5
      expect(result).to include('...')
    end
  end

  describe '.count_lines' do
    it 'counts lines correctly' do
      expect(described_class.count_lines("a\nb\nc")).to eq(3)
    end

    it 'returns 0 for nil' do
      expect(described_class.count_lines(nil)).to eq(0)
    end

    it 'returns 0 for empty string' do
      expect(described_class.count_lines('')).to eq(0)
    end

    it 'does not count trailing newline' do
      # count_lines subtracts 1 when text ends with "\n"
      expect(described_class.count_lines("a\nb\n")).to eq(1)
    end
  end

  describe '.format_bytes' do
    it 'formats bytes' do
      expect(described_class.format_bytes(500)).to eq('500B')
    end

    it 'formats kilobytes' do
      expect(described_class.format_bytes(2048)).to eq('2.0KB')
    end

    it 'formats megabytes' do
      expect(described_class.format_bytes(2_000_000)).to eq('1.9MB')
    end
  end

  describe '.estimate_tokens' do
    it 'returns 0 for nil' do
      expect(described_class.estimate_tokens(nil)).to eq(0)
    end

    it 'returns 0 for empty string' do
      expect(described_class.estimate_tokens('')).to eq(0)
    end

    it 'returns at least 1 token' do
      expect(described_class.estimate_tokens('a')).to eq(1)
    end

    it 'estimates ASCII text' do
      expect(described_class.estimate_tokens('a' * 8)).to eq(2)
    end
  end

  describe '.normalize_text_block' do
    it 'removes duplicate lines' do
      text = "line1\nline1\nline2"
      result = described_class.normalize_text_block(text)
      expect(result).to include('repeated')
    end

    it 'limits blank runs' do
      text = "a\n\n\n\n\nb"
      result = described_class.normalize_text_block(text)
      blank_count = result.split("\n").count { |l| l.strip.empty? }
      expect(blank_count).to be <= 2
    end
  end

  describe '.should_omit_base64?' do
    it 'returns true for data_base64 key with long value' do
      expect(described_class.should_omit_base64?('data_base64', 'a' * 300)).to be(true)
    end

    it 'returns true for data URL' do
      # should_omit_base64 requires value.length > 256
      long_data_url = "data:image/png;base64,#{'a' * 300}"
      expect(described_class.should_omit_base64?('data', long_data_url)).to be(true)
    end

    it 'returns false for short values' do
      expect(described_class.should_omit_base64?('data_base64', 'short')).to be(false)
    end

    it 'returns false for non-matching keys' do
      expect(described_class.should_omit_base64?('content', 'a' * 300)).to be(false)
    end
  end
end
