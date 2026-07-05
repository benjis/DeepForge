# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ToolCatalogFingerprint do
  describe '.build' do
    it 'returns fingerprint info with tool_count, tool_names, and tool_hashes' do
      tools = [
        { name: 'bash', description: 'run commands', input_schema: { type: 'object' } },
        { name: 'read', description: 'read files', input_schema: {} }
      ]
      result = described_class.build(tools)
      expect(result[:fingerprint]).to be_a(String)
      expect(result[:fingerprint].size).to eq(16)
      expect(result[:tool_count]).to eq(2)
      expect(result[:tool_names]).to eq(%w[bash read])
      expect(result[:tool_hashes]).to be_a(Hash)
      expect(result[:tool_hashes].keys).to contain_exactly('bash', 'read')
    end

    it 'produces same fingerprint for same tools regardless of order' do
      tools_a = [
        { name: 'bash', description: 'run' },
        { name: 'read', description: 'read' }
      ]
      tools_b = [
        { name: 'read', description: 'read' },
        { name: 'bash', description: 'run' }
      ]
      expect(described_class.build(tools_a)[:fingerprint]).to eq(described_class.build(tools_b)[:fingerprint])
    end

    it 'produces different fingerprint for different tools' do
      tools_a = [{ name: 'bash', description: 'run' }]
      tools_b = [{ name: 'read', description: 'read' }]
      expect(described_class.build(tools_a)[:fingerprint]).not_to eq(described_class.build(tools_b)[:fingerprint])
    end

    it 'returns empty arrays for empty tools' do
      result = described_class.build([])
      expect(result[:tool_count]).to eq(0)
      expect(result[:tool_names]).to eq([])
    end
  end

  describe '.normalize_tool_specs' do
    it 'handles string keys' do
      tools = [{ 'name' => 'bash', 'description' => 'run' }]
      result = described_class.normalize_tool_specs(tools)
      expect(result.first[:name]).to eq('bash')
    end

    it 'canonicalizes input_schema with sorted keys' do
      tools = [{ name: 'bash', input_schema: { z: 1, a: 2 } }]
      result = described_class.normalize_tool_specs(tools)
      expect(result.first[:input_schema].keys).to eq(%i[a z])
    end

    it 'defaults input_schema to empty hash' do
      tools = [{ name: 'bash' }]
      result = described_class.normalize_tool_specs(tools)
      expect(result.first[:input_schema]).to eq({})
    end
  end

  describe '.hash_object' do
    it 'returns 16-char hex string' do
      h = described_class.hash_object({ test: 1 })
      expect(h.size).to eq(16)
      expect(h).to match(/\A[0-9a-f]+\z/)
    end

    it 'is deterministic' do
      obj = { a: 1, b: [2, 3] }
      expect(described_class.hash_object(obj)).to eq(described_class.hash_object(obj))
    end

    it 'produces different hashes for different objects' do
      expect(described_class.hash_object({ a: 1 })).not_to eq(described_class.hash_object({ a: 2 }))
    end
  end
end
