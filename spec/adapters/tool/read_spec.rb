# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/read'

RSpec.describe DeepForge::Adapters::Tool do
  describe '.create_read_tool' do
    it 'returns a read tool definition' do
      tool = described_class.create_read_tool(nil)
      expect(tool[:name]).to eq('read')
      expect(tool[:description]).to include('file')
      expect(tool[:input_schema][:required]).to include('path')
    end

    it 'accepts custom options' do
      opts = DeepForge::Adapters::Tool::BuiltinReadTool::ReadToolOptions.new(max_lines: 100)
      tool = described_class.create_read_tool(opts)
      expect(tool[:name]).to eq('read')
    end
  end

  describe '.create_read_tool_definition' do
    it 'delegates to create_read_tool' do
      tool = described_class.create_read_tool_definition(nil)
      expect(tool[:name]).to eq('read')
    end
  end

  describe '.default_read_local_tool_operations' do
    it 'returns a ReadOperations struct' do
      ops = described_class.default_read_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::BuiltinReadTool::ReadOperations)
    end
  end

  describe 'ReadOperations alias' do
    it 'is aliased from BuiltinReadTool' do
      expect(described_class::ReadOperations).to eq(DeepForge::Adapters::Tool::BuiltinReadTool::ReadOperations)
    end
  end

  describe 'ReadToolOptions alias' do
    it 'is aliased from BuiltinReadTool' do
      expect(described_class::ReadToolOptions).to eq(DeepForge::Adapters::Tool::BuiltinReadTool::ReadToolOptions)
    end
  end

  describe 'ResizedImageResult alias' do
    it 'is aliased from BuiltinReadTool' do
      expect(described_class::ResizedImageResult).to eq(DeepForge::Adapters::Tool::BuiltinReadTool::ResizedImageResult)
    end
  end

  describe 'ResizeImageOptions alias' do
    it 'is aliased from BuiltinReadTool' do
      expect(described_class::ResizeImageOptions).to eq(DeepForge::Adapters::Tool::BuiltinReadTool::ResizeImageOptions)
    end
  end
end
