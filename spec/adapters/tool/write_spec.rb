# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/write'

RSpec.describe DeepForge::Adapters::Tool do
  describe '.create_write_tool' do
    it 'returns a write tool definition' do
      tool = described_class.create_write_tool(nil)
      expect(tool[:name]).to eq('write')
      expect(tool[:description]).to include('file')
      expect(tool[:input_schema][:required]).to include('path', 'content')
    end

    it 'accepts custom options' do
      opts = DeepForge::Adapters::Tool::BuiltinFileTools::WriteLocalToolOptions.new
      tool = described_class.create_write_tool(opts)
      expect(tool[:name]).to eq('write')
    end
  end

  describe '.create_write_tool_definition' do
    it 'delegates to create_write_tool' do
      tool = described_class.create_write_tool_definition(nil)
      expect(tool[:name]).to eq('write')
    end
  end

  describe '.default_write_local_tool_operations' do
    it 'returns a WriteLocalToolOperations struct' do
      ops = described_class.default_write_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::BuiltinFileTools::WriteLocalToolOperations)
    end
  end

  describe 'WriteOperations alias' do
    it 'is aliased from BuiltinFileTools' do
      expect(described_class::WriteOperations).to eq(DeepForge::Adapters::Tool::BuiltinFileTools::WriteLocalToolOperations)
    end
  end

  describe 'WriteToolOptions alias' do
    it 'is aliased from BuiltinFileTools' do
      expect(described_class::WriteToolOptions).to eq(DeepForge::Adapters::Tool::BuiltinFileTools::WriteLocalToolOptions)
    end
  end
end
