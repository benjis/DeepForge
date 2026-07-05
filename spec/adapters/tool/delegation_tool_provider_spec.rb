# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/delegation_tool_provider'

RSpec.describe DeepForge::Adapters::Tool::DelegationToolProvider do
  describe '.build' do
    it 'returns empty array for nil runtime' do
      expect(described_class.build(nil)).to eq([])
    end

    it 'returns tool provider with delegate_task tool' do
      runtime = double('runtime')
      providers = described_class.build(runtime)
      expect(providers.length).to eq(1)
      expect(providers.first[:id]).to eq('delegation')
      expect(providers.first[:kind]).to eq('delegation')
      expect(providers.first[:enabled]).to be true
      expect(providers.first[:tools].length).to eq(1)
      expect(providers.first[:tools].first[:name]).to eq('delegate_task')
    end
  end

  describe '.create_delegate_task_tool' do
    it 'creates a tool with correct schema' do
      runtime = double('runtime')
      tool = described_class.create_delegate_task_tool(runtime)
      expect(tool[:name]).to eq('delegate_task')
      expect(tool[:input_schema][:required]).to include('prompt')
      expect(tool[:policy]).to eq('auto')
    end

    it 'execute returns error for empty prompt' do
      runtime = double('runtime')
      tool = described_class.create_delegate_task_tool(runtime)
      result = tool[:execute].call({ prompt: '' }, {})
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('prompt is required')
    end

    it 'execute returns error for nil prompt' do
      runtime = double('runtime')
      tool = described_class.create_delegate_task_tool(runtime)
      result = tool[:execute].call({ prompt: nil }, {})
      expect(result[:is_error]).to be true
    end

    it 'execute calls runtime.run_child on success' do
      runtime = double('runtime')
      allow(runtime).to receive_messages(diagnostics: { child_runs: [] }, run_child: {
                                           id: 'child_1', status: 'completed', summary: 'done', error: nil, usage: {}
                                         })

      tool = described_class.create_delegate_task_tool(runtime)
      context = { thread_id: 't1', turn_id: 'r1', workspace: '/tmp' }
      result = tool[:execute].call({ prompt: 'do something' }, context)
      expect(result[:output][:status]).to eq('completed')
      expect(result[:output][:child_id]).to eq('child_1')
    end

    it 'execute returns error on exception' do
      runtime = double('runtime')
      allow(runtime).to receive(:diagnostics).and_raise('runtime error')

      tool = described_class.create_delegate_task_tool(runtime)
      context = { thread_id: 't1', turn_id: 'r1', workspace: '/tmp' }
      result = tool[:execute].call({ prompt: 'do something' }, context)
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('delegation failed')
    end

    it 'adds warning for subsequent spawns' do
      runtime = double('runtime')
      allow(runtime).to receive_messages(diagnostics: { child_runs: [{}] }, run_child: {
                                           id: 'child_2', status: 'completed', summary: 'done', error: nil, usage: {}
                                         })

      tool = described_class.create_delegate_task_tool(runtime)
      context = { thread_id: 't1', turn_id: 'r1', workspace: '/tmp' }
      result = tool[:execute].call({ prompt: 'do something' }, context)
      expect(result[:output][:warning]).to include('spawn #2')
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
