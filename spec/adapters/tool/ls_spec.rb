# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/ls'

RSpec.describe DeepForge::Adapters::Tool do
  describe '.create_ls_tool' do
    it 'returns an ls tool definition' do
      tool = described_class.create_ls_tool(nil)
      expect(tool[:name]).to eq('ls')
      expect(tool[:description]).to include('directory')
      expect(tool[:policy]).to eq('auto')
    end

    it 'accepts custom options' do
      opts = DeepForge::Adapters::Tool::BuiltinSearchTools::LsLocalToolOptions.new
      tool = described_class.create_ls_tool(opts)
      expect(tool[:name]).to eq('ls')
    end
  end

  describe '.create_ls_tool_definition' do
    it 'delegates to create_ls_tool' do
      tool = described_class.create_ls_tool_definition(nil)
      expect(tool[:name]).to eq('ls')
    end
  end

  describe '.default_ls_local_tool_operations' do
    it 'returns an LsOperations struct' do
      ops = described_class.default_ls_local_tool_operations
      expect(ops).to be_a(described_class::LsOperations)
      expect(ops.stat).to be_a(Proc)
      expect(ops.readdir).to be_a(Proc)
    end

    it 'stat returns file stat' do
      ops = described_class.default_ls_local_tool_operations
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test.txt')
        File.write(path, 'hello')
        stat = ops.stat.call(path)
        expect(stat.size).to eq(5)
      end
    end

    it 'readdir lists entries' do
      ops = described_class.default_ls_local_tool_operations
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.txt'), 'a')
        entries = ops.readdir.call(dir)
        names = entries.map { |e| e[:name] }
        expect(names).to include('a.txt')
      end
    end
  end

  describe 'LsOperations struct' do
    it 'has stat and readdir fields' do
      ops = described_class::LsOperations.new(stat: ->(p) {}, readdir: ->(p) {})
      expect(ops.stat).to be_a(Proc)
      expect(ops.readdir).to be_a(Proc)
    end
  end

  describe 'LsToolOptions alias' do
    it 'is aliased from BuiltinSearchTools' do
      expect(described_class::LsToolOptions).to eq(DeepForge::Adapters::Tool::BuiltinSearchTools::LsLocalToolOptions)
    end
  end
end
