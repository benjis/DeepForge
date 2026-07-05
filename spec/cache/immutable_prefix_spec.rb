# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ImmutablePrefixBuilder do
  describe '.create' do
    it 'creates prefix with fingerprint and revision 1' do
      prefix = described_class.create(system_prompt: 'You are helpful')
      expect(prefix).to be_a(ImmutablePrefix)
      expect(prefix.system_prompt).to eq('You are helpful')
      expect(prefix.fingerprint).to be_a(String)
      expect(prefix.fingerprint.size).to eq(16)
      expect(prefix.revision).to eq(1)
    end

    it 'normalizes tools by name' do
      prefix = described_class.create(tools: [
                                        { name: 'bash', description: 'run', input_schema: {} },
                                        { name: 'alpha', description: 'first', input_schema: {} }
                                      ])
      expect(prefix.tools.map { |t| t[:name] }).to eq(%w[alpha bash])
    end

    it 'defaults to empty arrays' do
      prefix = described_class.create
      expect(prefix.tools).to eq([])
      expect(prefix.pinned_constraints).to eq([])
      expect(prefix.few_shots).to eq([])
    end
  end

  describe '.mutate' do
    it 'increments revision' do
      original = described_class.create(system_prompt: 'v1')
      mutated = described_class.mutate(original, system_prompt: 'v2')
      expect(mutated.revision).to eq(2)
    end

    it 'changes fingerprint when system_prompt changes' do
      original = described_class.create(system_prompt: 'v1')
      mutated = described_class.mutate(original, system_prompt: 'v2')
      expect(mutated.fingerprint).not_to eq(original.fingerprint)
    end

    it 'does not mutate original' do
      original = described_class.create(system_prompt: 'v1')
      described_class.mutate(original, system_prompt: 'v2')
      expect(original.system_prompt).to eq('v1')
      expect(original.revision).to eq(1)
    end

    it 'preserves unchanged fields' do
      original = described_class.create(
        system_prompt: 'v1',
        tools: [{ name: 'bash', description: 'run', input_schema: {} }],
        pinned_constraints: ['rule1']
      )
      mutated = described_class.mutate(original, system_prompt: 'v2')
      expect(mutated.pinned_constraints).to eq(['rule1'])
      expect(mutated.tools.first[:name]).to eq('bash')
    end
  end

  describe '.set_system_prompt' do
    it 'updates system_prompt' do
      original = described_class.create(system_prompt: 'old')
      updated = described_class.set_system_prompt(original, 'new')
      expect(updated.system_prompt).to eq('new')
    end
  end

  describe '.set_tools' do
    it 'updates tools' do
      original = described_class.create
      updated = described_class.set_tools(original, [
                                            { name: 'bash', description: 'run', input_schema: {} }
                                          ])
      expect(updated.tools.size).to eq(1)
      expect(updated.tools.first[:name]).to eq('bash')
    end
  end

  describe '.verify' do
    it 'returns fingerprint when valid' do
      prefix = described_class.create(system_prompt: 'test')
      expect(described_class.verify(prefix)).to eq(prefix.fingerprint)
    end

    it 'raises RuntimeError on fingerprint drift' do
      prefix = described_class.create(system_prompt: 'test')
      prefix.system_prompt = 'tampered'
      expect { described_class.verify(prefix) }.to raise_error(RuntimeError, /fingerprint drift/)
    end
  end

  describe '.describe_fingerprint_drift' do
    it 'reports no drift for identical prefixes' do
      a = described_class.create(system_prompt: 'test')
      result = described_class.describe_fingerprint_drift(a, a.dup)
      expect(result[:drift]).to be(false)
      expect(result[:changed_fields]).to eq([])
    end

    it 'detects system_prompt change' do
      a = described_class.create(system_prompt: 'v1')
      b = described_class.mutate(a, system_prompt: 'v2')
      result = described_class.describe_fingerprint_drift(a, b)
      expect(result[:drift]).to be(true)
      expect(result[:changed_fields]).to include('systemPrompt')
    end

    it 'detects tools change' do
      a = described_class.create
      b = described_class.set_tools(a, [{ name: 'new_tool', description: 'x', input_schema: {} }])
      result = described_class.describe_fingerprint_drift(a, b)
      expect(result[:drift]).to be(true)
      expect(result[:changed_fields]).to include('tools')
    end
  end

  describe '.hash_object' do
    it 'returns a 16-char hex string' do
      h = described_class.hash_object({ a: 1 })
      expect(h.size).to eq(16)
      expect(h).to match(/\A[0-9a-f]+\z/)
    end

    it 'is deterministic' do
      a = described_class.hash_object({ x: 1, y: 2 })
      b = described_class.hash_object({ x: 1, y: 2 })
      expect(a).to eq(b)
    end
  end
end
