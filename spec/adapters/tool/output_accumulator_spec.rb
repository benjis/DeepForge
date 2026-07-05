# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/output_accumulator'

RSpec.describe DeepForge::Adapters::Tool::OutputAccumulator do
  subject(:accumulator) { described_class.new(options) }

  let(:options) do
    DeepForge::Adapters::Tool::OutputAccumulatorOptions.new(
      max_lines: 100,
      max_bytes: 10_000,
      temp_file_prefix: 'test-accumulator'
    )
  end

  describe '#append' do
    it 'accumulates data' do
      accumulator.append('hello ')
      accumulator.append('world')
      accumulator.finish
      snapshot = accumulator.snapshot
      expect(snapshot.content).to eq('hello world')
    end

    it 'tracks line counts' do
      accumulator.append("line1\nline2\nline3")
      accumulator.finish
      snapshot = accumulator.snapshot
      expect(snapshot.truncation[:total_lines]).to eq(3)
    end

    it 'tracks byte counts' do
      accumulator.append('hello')
      accumulator.finish
      snapshot = accumulator.snapshot
      expect(snapshot.truncation[:total_bytes]).to eq(5)
    end

    it 'raises when appending after finish' do
      accumulator.finish
      expect { accumulator.append('data') }.to raise_error(RuntimeError, /finished/)
    end
  end

  describe '#snapshot' do
    it 'returns content within limits' do
      accumulator.append('hello')
      accumulator.finish
      snapshot = accumulator.snapshot
      expect(snapshot.content).to eq('hello')
      expect(snapshot.truncation[:truncated]).to be false
    end

    it 'truncates when exceeding max_lines' do
      lines = (1..200).map { |i| "line#{i}" }.join("\n")
      accumulator.append(lines)
      accumulator.finish
      snapshot = accumulator.snapshot
      expect(snapshot.truncation[:truncated]).to be true
      expect(snapshot.truncation[:truncated_by]).to eq('lines')
    end

    it 'truncates when exceeding max_bytes' do
      big_text = 'a' * 20_000
      accumulator.append(big_text)
      accumulator.finish
      snapshot = accumulator.snapshot
      expect(snapshot.truncation[:truncated]).to be true
      expect(snapshot.truncation[:truncated_by]).to eq('bytes')
    end
  end

  describe '#finish' do
    it 'can be called multiple times safely' do
      accumulator.append('data')
      accumulator.finish
      expect { accumulator.finish }.not_to raise_error
    end
  end

  describe '#last_line_bytes' do
    it 'returns 0 for empty accumulator' do
      expect(accumulator.last_line_bytes).to eq(0)
    end

    it 'tracks bytes of current line' do
      accumulator.append('hello')
      expect(accumulator.last_line_bytes).to eq(5)
    end

    it 'resets after newline' do
      accumulator.append("hello\nworld")
      expect(accumulator.last_line_bytes).to eq(5)
    end
  end

  describe '#close_temp_file' do
    it 'closes temp file if open' do
      big_text = 'a' * 20_000
      accumulator.append(big_text)
      accumulator.close_temp_file
      expect(accumulator.instance_variable_get(:@temp_file)).to be_nil
    end

    it 'is safe when no temp file exists' do
      expect { accumulator.close_temp_file }.not_to raise_error
    end
  end

  describe 'temp file creation' do
    it 'creates temp file when data exceeds limits' do
      big_text = 'a' * 20_000
      accumulator.append(big_text)
      accumulator.finish
      path = accumulator.snapshot.full_output_path
      expect(path).not_to be_nil
      expect(File.exist?(path)).to be true
      FileUtils.rm_f(path)
    end
  end
end
