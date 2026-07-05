# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_tools'

RSpec.describe DeepForge::Adapters::Tool::BuiltinTools do
  describe '.create_builtin_local_tool' do
    it 'creates a read tool' do
      tool = described_class.create_builtin_local_tool('read')
      expect(tool).to be_a(DeepForge::Adapters::Tool::LocalTool)
      expect(tool.name).to eq('read')
    end

    it 'creates a bash tool' do
      tool = described_class.create_builtin_local_tool('bash')
      expect(tool.name).to eq('bash')
    end

    it 'creates an edit tool' do
      tool = described_class.create_builtin_local_tool('edit')
      expect(tool.name).to eq('edit')
    end

    it 'creates a write tool' do
      tool = described_class.create_builtin_local_tool('write')
      expect(tool.name).to eq('write')
    end

    it 'creates a grep tool' do
      tool = described_class.create_builtin_local_tool('grep')
      expect(tool.name).to eq('grep')
    end

    it 'creates a find tool' do
      tool = described_class.create_builtin_local_tool('find')
      expect(tool.name).to eq('find')
    end

    it 'creates an ls tool' do
      tool = described_class.create_builtin_local_tool('ls')
      expect(tool.name).to eq('ls')
    end

    it 'raises for unknown tool' do
      expect do
        described_class.create_builtin_local_tool('unknown')
      end.to raise_error(RuntimeError, /unknown tool/)
    end
  end

  describe '.create_tool' do
    it 'delegates to create_builtin_local_tool' do
      tool = described_class.create_tool('read')
      expect(tool.name).to eq('read')
    end
  end

  describe '.create_tool_definition' do
    it 'delegates to create_builtin_local_tool' do
      tool = described_class.create_tool_definition('bash')
      expect(tool.name).to eq('bash')
    end
  end

  describe '.build_builtin_local_tools' do
    it 'returns all 7 builtin tools' do
      tools = described_class.build_builtin_local_tools
      expect(tools.length).to eq(7)
      names = tools.map(&:name)
      expect(names).to contain_exactly('read', 'bash', 'edit', 'write', 'grep', 'find', 'ls')
    end
  end

  describe '.create_all_tools' do
    it 'returns a hash of tools' do
      tools = described_class.create_all_tools
      expect(tools).to be_a(Hash)
      expect(tools.keys).to contain_exactly('read', 'bash', 'edit', 'write', 'grep', 'find', 'ls')
    end
  end

  describe '.build_coding_builtin_local_tools' do
    it 'returns coding tools only' do
      tools = described_class.build_coding_builtin_local_tools
      expect(tools.length).to eq(4)
      names = tools.map(&:name)
      expect(names).to contain_exactly('read', 'bash', 'edit', 'write')
    end
  end

  describe '.build_read_only_builtin_local_tools' do
    it 'returns read-only tools' do
      tools = described_class.build_read_only_builtin_local_tools
      expect(tools.length).to eq(4)
      names = tools.map(&:name)
      expect(names).to contain_exactly('read', 'grep', 'find', 'ls')
    end
  end

  describe 'tool execution' do
    let(:workspace) { Dir.mktmpdir('deepforge-test') }

    after { FileUtils.remove_entry(workspace) }

    it 'read tool reads file content' do
      tool = described_class.create_builtin_local_tool('read')
      File.write(File.join(workspace, 'test.txt'), 'hello')
      context = Struct.new(:workspace, :abort_signal, :thread_id, :turn_id, :approval_policy).new(
        workspace, nil, 't1', 'r1', 'auto'
      )
      result = tool.execute.call({ path: 'test.txt' }, context)
      expect(result[:output][:content]).to include('hello')
    end

    it 'write tool writes file content' do
      tool = described_class.create_builtin_local_tool('write')
      context = Struct.new(:workspace, :abort_signal, :thread_id, :turn_id, :approval_policy).new(
        workspace, nil, 't1', 'r1', 'auto'
      )
      tool.execute.call({ path: 'test.txt', content: 'hello' }, context)
      expect(File.read(File.join(workspace, 'test.txt'))).to eq('hello')
    end
  end
end
