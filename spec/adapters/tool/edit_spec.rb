# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/edit'

RSpec.describe DeepForge::Adapters::Tool do
  describe '.create_edit_tool' do
    it 'returns an edit tool definition' do
      tool = described_class.create_edit_tool(nil)
      expect(tool[:name]).to eq('edit')
      expect(tool[:description]).to include('edit')
      expect(tool[:input_schema][:required]).to include('path')
    end

    it 'accepts custom options' do
      opts = DeepForge::Adapters::Tool::BuiltinFileTools::EditLocalToolOptions.new
      tool = described_class.create_edit_tool(opts)
      expect(tool[:name]).to eq('edit')
    end
  end

  describe '.create_edit_tool_definition' do
    it 'delegates to create_edit_tool' do
      tool = described_class.create_edit_tool_definition(nil)
      expect(tool[:name]).to eq('edit')
    end
  end

  describe '.default_edit_local_tool_operations' do
    it 'returns an EditLocalToolOperations struct' do
      ops = described_class.default_edit_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::BuiltinFileTools::EditLocalToolOperations)
    end
  end

  describe 'EditOperations alias' do
    it 'is aliased from BuiltinFileTools' do
      expect(described_class::EditOperations).to eq(DeepForge::Adapters::Tool::BuiltinFileTools::EditLocalToolOperations)
    end
  end

  describe 'EditToolOptions alias' do
    it 'is aliased from BuiltinFileTools' do
      expect(described_class::EditToolOptions).to eq(DeepForge::Adapters::Tool::BuiltinFileTools::EditLocalToolOptions)
    end
  end
end
