# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_search_tools'

RSpec.describe DeepForge::Adapters::Tool::BuiltinSearchTools do
  let(:workspace) { Dir.mktmpdir('deepforge-test') }

  after { FileUtils.remove_entry(workspace) }

  describe '.create_ls_tool' do
    it 'returns an ls tool definition' do
      tool = described_class.create_ls_tool(nil)
      expect(tool[:name]).to eq('ls')
      expect(tool[:description]).to include('directory')
      expect(tool[:policy]).to eq('auto')
    end
  end

  describe '.create_find_tool' do
    it 'returns a find tool definition' do
      tool = described_class.create_find_tool(nil)
      expect(tool[:name]).to eq('find')
      expect(tool[:description]).to include('Find')
      expect(tool[:input_schema][:required]).to include('pattern')
    end
  end

  describe '.create_grep_tool' do
    it 'returns a grep tool definition' do
      tool = described_class.create_grep_tool(nil)
      expect(tool[:name]).to eq('grep')
      expect(tool[:description]).to include('Search')
      expect(tool[:input_schema][:required]).to include('pattern')
    end
  end

  describe '.execute_ls' do
    it 'lists directory contents' do
      File.write(File.join(workspace, 'a.txt'), 'a')
      FileUtils.mkdir_p(File.join(workspace, 'sub'))
      options = described_class::LsLocalToolOptions.new
      result = described_class.execute_ls(
        { path: '.' },
        { workspace: workspace },
        options
      )
      expect(result[:output][:entries].length).to eq(2)
      names = result[:output][:entries].map { |e| e[:name] }
      expect(names).to include('a.txt', 'sub')
    end

    it 'returns error for non-directory' do
      File.write(File.join(workspace, 'file.txt'), 'content')
      options = described_class::LsLocalToolOptions.new
      result = described_class.execute_ls(
        { path: 'file.txt' },
        { workspace: workspace },
        options
      )
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('not a directory')
    end
  end

  describe '.execute_find' do
    it 'finds files by pattern' do
      File.write(File.join(workspace, 'test.rb'), 'puts 1')
      File.write(File.join(workspace, 'test.py'), 'print(1)')
      options = described_class::FindLocalToolOptions.new
      result = described_class.execute_find(
        { pattern: '*.rb' },
        { workspace: workspace },
        options
      )
      expect(result[:output][:matches].length).to eq(1)
      expect(result[:output][:matches].first[:path]).to include('test.rb')
    end

    it 'returns error for empty pattern' do
      options = described_class::FindLocalToolOptions.new
      result = described_class.execute_find(
        { pattern: '' },
        { workspace: workspace },
        options
      )
      expect(result[:is_error]).to be true
    end
  end

  describe '.execute_grep' do
    it 'searches file contents' do
      File.write(File.join(workspace, 'test.txt'), "hello\nworld\nhello again")
      options = described_class::GrepLocalToolOptions.new
      result = described_class.execute_grep(
        { pattern: 'hello' },
        { workspace: workspace },
        options
      )
      expect(result[:output][:matches].length).to eq(2)
    end

    it 'returns error for empty pattern' do
      options = described_class::GrepLocalToolOptions.new
      result = described_class.execute_grep(
        { pattern: '' },
        { workspace: workspace },
        options
      )
      expect(result[:is_error]).to be true
    end

    it 'supports ignore_case' do
      File.write(File.join(workspace, 'test.txt'), "Hello\nworld")
      options = described_class::GrepLocalToolOptions.new
      result = described_class.execute_grep(
        { pattern: 'hello', ignore_case: true },
        { workspace: workspace },
        options
      )
      expect(result[:output][:matches].length).to eq(1)
    end

    it 'supports literal matching' do
      File.write(File.join(workspace, 'test.txt'), "hello.world\nhelloXworld")
      options = described_class::GrepLocalToolOptions.new
      result = described_class.execute_grep(
        { pattern: 'hello.world', literal: true },
        { workspace: workspace },
        options
      )
      expect(result[:output][:matches].length).to eq(1)
    end

    it 'supports context lines' do
      File.write(File.join(workspace, 'test.txt'), "line1\nmatch\nline3")
      options = described_class::GrepLocalToolOptions.new
      result = described_class.execute_grep(
        { pattern: 'match', context: 1 },
        { workspace: workspace },
        options
      )
      expect(result[:output][:matches].first[:context_before]).to be_a(Array)
      expect(result[:output][:matches].first[:context_after]).to be_a(Array)
    end
  end

  describe '.list_directory' do
    it 'lists entries' do
      File.write(File.join(workspace, 'a.txt'), 'a')
      FileUtils.mkdir_p(File.join(workspace, 'sub'))
      entries = described_class.list_directory(workspace, workspace, 100)
      expect(entries.length).to eq(2)
      expect(entries.map(&:name)).to include('a.txt', 'sub')
    end

    it 'respects limit' do
      5.times { |i| File.write(File.join(workspace, "f#{i}.txt"), 'x') }
      entries = described_class.list_directory(workspace, workspace, 2)
      expect(entries.length).to eq(2)
    end
  end

  describe '.binary_file?' do
    it 'detects binary files' do
      path = File.join(workspace, 'binary.bin')
      File.binwrite(path, "hello\x00world")
      expect(described_class.binary_file?(path)).to be true
    end

    it 'detects text files' do
      path = File.join(workspace, 'text.txt')
      File.write(path, 'hello world')
      expect(described_class.binary_file?(path)).to be false
    end
  end

  describe '.normalize_positive_integer' do
    it 'returns default for nil' do
      expect(described_class.normalize_positive_integer(nil, 10)).to eq(10)
    end

    it 'returns positive value' do
      expect(described_class.normalize_positive_integer(5, 10)).to eq(5)
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
