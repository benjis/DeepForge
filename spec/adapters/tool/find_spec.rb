# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/find'

RSpec.describe DeepForge::Adapters::Tool do
  describe '.create_find_tool' do
    it 'returns a find tool definition' do
      tool = described_class.create_find_tool(nil)
      expect(tool[:name]).to eq('find')
      expect(tool[:description]).to include('Find')
      expect(tool[:input_schema][:required]).to include('pattern')
    end

    it 'accepts custom options' do
      opts = DeepForge::Adapters::Tool::BuiltinSearchTools::FindLocalToolOptions.new
      tool = described_class.create_find_tool(opts)
      expect(tool[:name]).to eq('find')
    end
  end

  describe '.create_find_tool_definition' do
    it 'delegates to create_find_tool' do
      tool = described_class.create_find_tool_definition(nil)
      expect(tool[:name]).to eq('find')
    end
  end

  describe '.default_find_local_tool_operations' do
    it 'returns a FindOperations struct' do
      ops = described_class.default_find_local_tool_operations
      expect(ops).to be_a(described_class::FindOperations)
      expect(ops.glob).to be_nil
    end
  end

  describe 'FindOperations struct' do
    it 'has glob field' do
      ops = described_class::FindOperations.new(glob: nil)
      expect(ops.glob).to be_nil
    end
  end

  describe 'FindToolOptions alias' do
    it 'is aliased from BuiltinSearchTools' do
      expect(described_class::FindToolOptions).to eq(DeepForge::Adapters::Tool::BuiltinSearchTools::FindLocalToolOptions)
    end
  end
end
