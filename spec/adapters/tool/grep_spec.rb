# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/grep'

RSpec.describe DeepForge::Adapters::Tool do
  describe '.create_grep_tool' do
    it 'returns a grep tool definition' do
      tool = described_class.create_grep_tool(nil)
      expect(tool[:name]).to eq('grep')
      expect(tool[:description]).to include('Search')
      expect(tool[:input_schema][:required]).to include('pattern')
    end

    it 'accepts custom options' do
      opts = DeepForge::Adapters::Tool::BuiltinSearchTools::GrepLocalToolOptions.new
      tool = described_class.create_grep_tool(opts)
      expect(tool[:name]).to eq('grep')
    end
  end

  describe '.create_grep_tool_definition' do
    it 'delegates to create_grep_tool' do
      tool = described_class.create_grep_tool_definition(nil)
      expect(tool[:name]).to eq('grep')
    end
  end

  describe '.default_grep_local_tool_operations' do
    it 'returns a GrepOperations struct' do
      ops = described_class.default_grep_local_tool_operations
      expect(ops).to be_a(described_class::GrepOperations)
      expect(ops.search).to be_nil
    end
  end

  describe 'GrepOperations struct' do
    it 'has search field' do
      ops = described_class::GrepOperations.new(search: nil)
      expect(ops.search).to be_nil
    end
  end

  describe 'GrepToolOptions alias' do
    it 'is aliased from BuiltinSearchTools' do
      expect(described_class::GrepToolOptions).to eq(DeepForge::Adapters::Tool::BuiltinSearchTools::GrepLocalToolOptions)
    end
  end
end
