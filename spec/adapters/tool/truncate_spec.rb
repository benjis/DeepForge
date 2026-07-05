# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/truncate'

RSpec.describe DeepForge::Adapters::Tool::Truncate do
  describe '.format_size' do
    it 'formats bytes less than 1024' do
      expect(described_class.format_size(512)).to eq('512B')
    end

    it 'formats kilobytes' do
      expect(described_class.format_size(1536)).to eq('1.5KB')
    end

    it 'formats megabytes' do
      expect(described_class.format_size(2 * 1024 * 1024)).to eq('2.0MB')
    end

    it 'formats zero bytes' do
      expect(described_class.format_size(0)).to eq('0B')
    end

    it 'formats exactly 1024 bytes' do
      expect(described_class.format_size(1024)).to eq('1.0KB')
    end
  end

  describe '.truncate_head' do
    it 'returns content unchanged when within limits' do
      result = described_class.truncate_head("line1\nline2", max_lines: 10, max_bytes: 1000)
      expect(result.content).to eq("line1\nline2")
      expect(result.truncated).to be false
      expect(result.total_lines).to eq(2)
    end

    it 'truncates when exceeding max_lines' do
      text = (1..100).map { |i| "line#{i}" }.join("\n")
      result = described_class.truncate_head(text, max_lines: 5, max_bytes: 100_000)
      expect(result.truncated).to be true
      expect(result.output_lines).to eq(5)
      expect(result.truncated_by).to eq('lines')
      expect(result.content.lines.length).to eq(5)
    end

    it 'truncates when exceeding max_bytes' do
      text = 'a' * 1000
      result = described_class.truncate_head(text, max_lines: 10_000, max_bytes: 100)
      expect(result.truncated).to be true
      expect(result.truncated_by).to eq('bytes')
      expect(result.output_bytes).to be <= 100
    end

    it 'handles first line exceeding max_bytes' do
      text = 'a' * 200
      result = described_class.truncate_head(text, max_lines: 10_000, max_bytes: 100)
      expect(result.truncated).to be true
      expect(result.first_line_exceeds_limit).to be true
      expect(result.output_lines).to eq(0)
    end

    it 'handles empty content' do
      result = described_class.truncate_head('', max_lines: 10, max_bytes: 1000)
      expect(result.truncated).to be false
      expect(result.total_lines).to eq(0)
      expect(result.content).to eq('')
    end

    it 'uses default limits' do
      result = described_class.truncate_head('hello')
      expect(result.truncated).to be false
      expect(result.max_lines).to eq(DeepForge::Adapters::Tool::DEFAULT_MAX_LINES)
    end
  end

  describe '.truncate_tail' do
    it 'returns content unchanged when within limits' do
      result = described_class.truncate_tail("line1\nline2", max_lines: 10, max_bytes: 1000)
      expect(result.content).to eq("line1\nline2")
      expect(result.truncated).to be false
    end

    it 'truncates from the tail when exceeding max_lines' do
      text = (1..100).map { |i| "line#{i}" }.join("\n")
      result = described_class.truncate_tail(text, max_lines: 5, max_bytes: 100_000)
      expect(result.truncated).to be true
      expect(result.output_lines).to eq(5)
      expect(result.content).to include('line100')
      expect(result.content.lines.first.chomp).to eq('line96')
    end

    it 'truncates by bytes from the tail' do
      text = (1..100).map { |i| "line#{i}" }.join("\n")
      result = described_class.truncate_tail(text, max_lines: 10_000, max_bytes: 50)
      expect(result.truncated).to be true
      expect(result.output_bytes).to be <= 50
    end

    it 'handles single line exceeding max_bytes' do
      text = 'a' * 200
      result = described_class.truncate_tail(text, max_lines: 10_000, max_bytes: 100)
      expect(result.truncated).to be true
      expect(result.last_line_partial).to be true
    end

    it 'handles empty content' do
      result = described_class.truncate_tail('', max_lines: 10, max_bytes: 1000)
      expect(result.truncated).to be false
      expect(result.total_lines).to eq(0)
    end
  end
end
