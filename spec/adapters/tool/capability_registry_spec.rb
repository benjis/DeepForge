# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/capability_registry'
require_relative '../../../lib/deepforge/adapters/tool/local_tool_host'

RSpec.describe DeepForge::Adapters::Tool::CapabilityRegistry do
  let(:tool_definition) do
    DeepForge::Adapters::Tool::LocalToolHost.define_tool(
      name: 'test_tool',
      description: 'A test tool',
      input_schema: { type: 'object' },
      tool_kind: 'tool_call',
      policy: 'auto',
      execute: ->(args, _ctx) { { output: { result: args[:input] } } }
    )
  end

  let(:provider) do
    DeepForge::Adapters::Tool::CapabilityToolProvider.new(
      id: 'test_provider',
      kind: 'builtin',
      enabled: true,
      available: true,
      tools: [tool_definition]
    )
  end

  describe '#initialize' do
    it 'creates an empty registry' do
      registry = described_class.new
      expect(registry.instance_variable_get(:@tools)).to be_empty
    end
  end

  describe '#register_provider' do
    it 'registers a new provider without raising' do
      registry = described_class.new
      expect { registry.register_provider(provider) }.not_to raise_error
      expect(registry.instance_variable_get(:@providers)).to have_key('test_provider')
    end

    it 'raises on duplicate provider id' do
      registry = described_class.new([provider])
      expect do
        registry.register_provider(provider)
      end.to raise_error(RuntimeError, /duplicate tool provider/)
    end

    it 'raises on duplicate tool name' do
      registry = described_class.new
      registry.register_provider(provider)
      duplicate_provider = DeepForge::Adapters::Tool::CapabilityToolProvider.new(
        id: 'other', kind: 'builtin', enabled: true, available: true,
        tools: [tool_definition]
      )
      expect do
        registry.register_provider(duplicate_provider)
      end.to raise_error(RuntimeError, /duplicate tool name/)
    end
  end

  describe '#diagnostics' do
    it 'returns diagnostics for all providers' do
      registry = described_class.new([provider])
      diagnostics = registry.diagnostics
      expect(diagnostics.length).to eq(1)
      expect(diagnostics.first[:id]).to eq('test_provider')
      expect(diagnostics.first[:kind]).to eq('builtin')
      expect(diagnostics.first[:enabled]).to be true
      expect(diagnostics.first[:available]).to be true
    end
  end

  describe 'struct types' do
    it 'CapabilityToolProvider has expected fields' do
      p = DeepForge::Adapters::Tool::CapabilityToolProvider.new(
        id: 'a', kind: 'b', enabled: true, available: true, tools: []
      )
      expect(p.id).to eq('a')
      expect(p.enabled).to be true
    end

    it 'CapabilityToolRecord has expected fields' do
      r = DeepForge::Adapters::Tool::CapabilityToolRecord.new(provider: { id: 'a' }, tool: tool_definition)
      expect(r.tool.name).to eq('test_tool')
    end

    it 'CapabilityToolSpec has expected fields' do
      s = DeepForge::Adapters::Tool::CapabilityToolSpec.new(
        name: 'test', description: 'desc', input_schema: {}, tool_kind: 'tool_call',
        provider_id: 'p', provider_kind: 'builtin'
      )
      expect(s.name).to eq('test')
    end
  end
end
