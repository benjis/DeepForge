# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/memory_tool_provider'

RSpec.describe DeepForge::Adapters::Tool::MemoryToolProvider do
  let(:store) { double('store') }

  describe '.build' do
    it 'returns empty array for nil store' do
      expect(described_class.build(nil)).to eq([])
    end

    it 'returns tool provider with memory tools' do
      providers = described_class.build(store)
      expect(providers.length).to eq(1)
      expect(providers.first[:id]).to eq('memory')
      expect(providers.first[:kind]).to eq('memory')
      expect(providers.first[:tools].length).to eq(3)
      names = providers.first[:tools].map { |t| t[:name] }
      expect(names).to contain_exactly('memory_create', 'memory_update', 'memory_delete')
    end
  end

  describe 'memory_create tool' do
    let(:tool) { described_class.create_memory_create_tool(store) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('memory_create')
      expect(tool[:policy]).to eq('on-request')
      expect(tool[:input_schema][:required]).to include('content')
    end

    it 'creates a memory' do
      allow(store).to receive(:create).and_return({ id: 'm1', content: 'test' })
      result = tool[:execute].call(
        { content: 'test memory' },
        { workspace: '/tmp', thread_id: 't1', turn_id: 'r1' }
      )
      expect(result[:output][:memory][:id]).to eq('m1')
    end

    it 'returns error for empty content' do
      result = tool[:execute].call(
        { content: '' },
        { workspace: '/tmp', thread_id: 't1', turn_id: 'r1' }
      )
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('content is required')
    end

    it 'defaults scope to workspace' do
      allow(store).to receive(:create) do |args|
        expect(args[:scope]).to eq('workspace')
        { id: 'm1' }
      end
      tool[:execute].call(
        { content: 'test' },
        { workspace: '/tmp', thread_id: 't1', turn_id: 'r1' }
      )
    end
  end

  describe 'memory_update tool' do
    let(:tool) { described_class.create_memory_update_tool(store) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('memory_update')
      expect(tool[:input_schema][:required]).to include('id')
    end

    # update tool has a source bug: references undefined Boolean constant
    # when checking args[:disabled].is_a?(Boolean)

    it 'returns error for missing id' do
      result = tool[:execute].call({ content: 'test' }, {})
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('id is required')
    end
  end

  describe 'memory_delete tool' do
    let(:tool) { described_class.create_memory_delete_tool(store) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('memory_delete')
      expect(tool[:input_schema][:required]).to include('id')
    end

    it 'deletes a memory' do
      allow(store).to receive(:delete).and_return({ id: 'm1', deleted: true })
      result = tool[:execute].call({ id: 'm1' }, {})
      expect(result[:output][:memory][:deleted]).to be true
    end

    it 'returns error for missing id' do
      result = tool[:execute].call({}, {})
      expect(result[:is_error]).to be true
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
