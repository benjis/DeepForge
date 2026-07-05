# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/bash'

RSpec.describe DeepForge::Adapters::Tool do
  describe '.create_bash_tool' do
    it 'returns a bash tool definition' do
      tool = described_class.create_bash_tool(nil)
      expect(tool[:name]).to eq('bash')
      expect(tool[:description]).to include('shell command')
      expect(tool[:input_schema][:required]).to include('command')
    end

    it 'accepts custom options' do
      opts = DeepForge::Adapters::Tool::BuiltinBashTool::BashToolOptions.new(default_timeout_seconds: 30)
      tool = described_class.create_bash_tool(opts)
      expect(tool[:name]).to eq('bash')
    end
  end

  describe '.create_bash_tool_definition' do
    it 'delegates to create_bash_tool' do
      tool = described_class.create_bash_tool_definition(nil)
      expect(tool[:name]).to eq('bash')
    end
  end

  describe '.create_local_bash_operations' do
    it 'returns a BashOperations struct' do
      ops = described_class.create_local_bash_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::BuiltinBashTool::BashOperations)
    end
  end

  describe 'BashOperations alias' do
    it 'is aliased from BuiltinBashTool' do
      expect(described_class::BashOperations).to eq(DeepForge::Adapters::Tool::BuiltinBashTool::BashOperations)
    end
  end

  describe 'BashToolOptions alias' do
    it 'is aliased from BuiltinBashTool' do
      expect(described_class::BashToolOptions).to eq(DeepForge::Adapters::Tool::BuiltinBashTool::BashToolOptions)
    end
  end
end
