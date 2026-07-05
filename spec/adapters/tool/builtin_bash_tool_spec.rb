# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_bash_tool'

RSpec.describe DeepForge::Adapters::Tool::BuiltinBashTool do
  describe '.create' do
    it 'returns a tool definition hash' do
      tool = described_class.create(nil)
      expect(tool[:name]).to eq('bash')
      expect(tool[:description]).to include('shell command')
      expect(tool[:input_schema][:required]).to include('command')
      expect(tool[:execute]).to be_a(Proc)
    end

    it 'accepts custom options' do
      opts = described_class::BashToolOptions.new(default_timeout_seconds: 30)
      tool = described_class.create(opts)
      expect(tool[:name]).to eq('bash')
    end
  end

  describe '.create_operations' do
    it 'returns a BashOperations struct' do
      ops = described_class.create_operations
      expect(ops).to be_a(described_class::BashOperations)
      expect(ops.exec).to be_nil
    end
  end

  describe '.truncate_output' do
    it 'returns content unchanged when within limits' do
      result = described_class.truncate_output("hello\nworld")
      expect(result[:content]).to eq("hello\nworld")
      expect(result[:truncated]).to be false
      expect(result[:total_lines]).to eq(2)
    end

    it 'truncates by lines when exceeding limit' do
      text = (1..3000).map { |i| "line#{i}" }.join("\n")
      result = described_class.truncate_output(text)
      expect(result[:truncated]).to be true
      expect(result[:truncated_by]).to eq('lines')
      expect(result[:output_lines]).to eq(described_class::DEFAULT_MAX_LINES)
    end

    it 'truncates by bytes when exceeding limit' do
      text = 'a' * (described_class::DEFAULT_MAX_BYTES + 1000)
      result = described_class.truncate_output(text)
      expect(result[:truncated]).to be true
      expect(result[:output_bytes]).to be <= described_class::DEFAULT_MAX_BYTES
    end
  end

  describe '.build_text_slice' do
    it 'creates a TextSlice from truncated info' do
      info = {
        content: 'hello',
        truncated: true,
        total_lines: 10,
        output_lines: 5,
        total_bytes: 100,
        output_bytes: 50,
        truncated_by: 'lines',
        last_line_partial: false
      }
      slice = described_class.build_text_slice(info)
      expect(slice).to be_a(described_class::TextSlice)
      expect(slice.text).to eq('hello')
      expect(slice.truncated).to be true
      expect(slice.total_lines).to eq(10)
      expect(slice.shown_lines).to eq(5)
    end
  end

  describe '.append_truncation_notice' do
    it 'returns text unchanged when not truncated' do
      result = described_class.append_truncation_notice('hello', nil, :tail)
      expect(result).to eq('hello')
    end

    it 'appends truncation notice' do
      slice = described_class::TextSlice.new(
        truncated: true, shown_lines: 5, total_lines: 10,
        shown_bytes: 50, total_bytes: 100, first_line_exceeds_limit: false
      )
      result = described_class.append_truncation_notice('hello', slice, :tail)
      expect(result).to include('truncated')
      expect(result).to include('5 of 10')
    end
  end

  describe '.format_truncation' do
    it 'returns nil when not truncated' do
      expect(described_class.format_truncation(nil)).to be_nil
    end

    it 'returns truncation info when truncated' do
      slice = described_class::TextSlice.new(
        truncated: true, shown_lines: 5, total_lines: 10,
        shown_bytes: 50, total_bytes: 100, truncated_by: 'lines', last_line_partial: false
      )
      result = described_class.format_truncation(slice)
      expect(result[:total_lines]).to eq(10)
      expect(result[:output_lines]).to eq(5)
    end
  end

  describe '.normalize_positive_integer' do
    it 'returns default for nil' do
      expect(described_class.normalize_positive_integer(nil, 10)).to eq(10)
    end

    it 'returns positive integer' do
      expect(described_class.normalize_positive_integer(5, 10)).to eq(5)
    end

    it 'returns default for zero' do
      expect(described_class.normalize_positive_integer(0, 10)).to eq(10)
    end

    it 'returns default for negative' do
      expect(described_class.normalize_positive_integer(-1, 10)).to eq(10)
    end
  end

  describe '.error_output' do
    it 'returns error hash' do
      result = described_class.error_output('test error')
      expect(result[:output][:error]).to eq('test error')
      expect(result[:is_error]).to be true
    end
  end

  describe '.execute_bash' do
    it 'returns error for empty command' do
      ops = described_class.create_operations
      opts = described_class::BashToolOptions.new
      result = described_class.execute_bash({ command: '' }, { workspace: Dir.tmpdir }, ops, opts)
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('command is required')
    end

    it 'returns error for nil command' do
      ops = described_class.create_operations
      opts = described_class::BashToolOptions.new
      result = described_class.execute_bash({ command: nil }, { workspace: Dir.tmpdir }, ops, opts)
      expect(result[:is_error]).to be true
    end

    it 'executes a successful command' do
      ops = described_class.create_operations
      opts = described_class::BashToolOptions.new
      result = described_class.execute_bash(
        { command: 'echo hello' }, { workspace: Dir.tmpdir }, ops, opts
      )
      expect(result[:output][:output]).to include('hello')
      expect(result[:output][:exit_code]).to eq(0)
      expect(result[:is_error]).to be_nil
    end

    it 'marks non-zero exit as error' do
      ops = described_class.create_operations
      opts = described_class::BashToolOptions.new
      result = described_class.execute_bash(
        { command: 'exit 1' }, { workspace: Dir.tmpdir }, ops, opts
      )
      expect(result[:is_error]).to be true
      expect(result[:output][:exit_code]).to eq(1)
    end

    it 'uses custom exec function when provided' do
      exec_fn = ->(_command, _cwd, _options) { { exit_code: 0 } }
      ops = described_class::BashOperations.new(exec: exec_fn)
      opts = described_class::BashToolOptions.new
      result = described_class.execute_bash(
        { command: 'test' }, { workspace: Dir.tmpdir }, ops, opts
      )
      expect(result[:output][:exit_code]).to eq(0)
    end

    it 'uses custom timeout from options' do
      ops = described_class.create_operations
      opts = described_class::BashToolOptions.new(default_timeout_seconds: 5)
      result = described_class.execute_bash(
        { command: 'echo fast' }, { workspace: Dir.tmpdir }, ops, opts
      )
      expect(result[:output][:output]).to include('fast')
    end
  end
end
