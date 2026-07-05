# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MemoryStore do
  describe '.create_record' do
    it 'creates a record with timestamps' do
      record = described_class.create_record(id: 'm1', content: 'remember this')
      expect(record.id).to eq('m1')
      expect(record.content).to eq('remember this')
      expect(record.scope).to eq('workspace')
      expect(record.created_at).to match(/\d{4}-\d{2}-\d{2}T/)
      expect(record.updated_at).to match(/\d{4}-\d{2}-\d{2}T/)
      expect(record.confidence).to eq(1.0)
      expect(record.tags).to eq([])
    end

    it 'uses provided parameters' do
      record = described_class.create_record(
        id: 'm2', content: 'test', scope: 'user',
        workspace: '/ws', project: 'p1', tags: ['t1'], confidence: 0.8
      )
      expect(record.scope).to eq('user')
      expect(record.workspace).to eq('/ws')
      expect(record.project).to eq('p1')
      expect(record.tags).to eq(['t1'])
      expect(record.confidence).to eq(0.8)
    end
  end

  describe '.to_hash' do
    it 'converts record to hash with all fields' do
      record = described_class.create_record(id: 'm1', content: 'test')
      hash = described_class.to_hash(record)
      expect(hash[:id]).to eq('m1')
      expect(hash[:content]).to eq('test')
      expect(hash).to have_key(:scope)
      expect(hash).to have_key(:created_at)
      expect(hash).to have_key(:deleted_at)
      expect(hash).to have_key(:disabled_at)
    end
  end

  describe '.from_hash' do
    it 'reconstructs record from hash with string keys' do
      hash = {
        'id' => 'm1', 'content' => 'test', 'scope' => 'workspace',
        'tags' => ['a'], 'confidence' => 0.5, 'created_at' => '2025-01-01T00:00:00Z'
      }
      record = described_class.from_hash(hash)
      expect(record.id).to eq('m1')
      expect(record.content).to eq('test')
      expect(record.tags).to eq(['a'])
      expect(record.confidence).to eq(0.5)
    end

    it 'reconstructs record from hash with symbol keys' do
      hash = { id: 'm1', content: 'test', scope: 'project' }
      record = described_class.from_hash(hash)
      expect(record.id).to eq('m1')
    end

    it 'defaults missing optional fields' do
      hash = { 'id' => 'm1', 'content' => 'test' }
      record = described_class.from_hash(hash)
      expect(record.tags).to eq([])
      expect(record.confidence).to eq(1.0)
    end
  end

  describe '.to_hash and .from_hash roundtrip' do
    it 'preserves all data through serialization roundtrip' do
      original = described_class.create_record(
        id: 'm1', content: 'test content', scope: 'user',
        tags: %w[tag1 tag2], confidence: 0.75
      )
      hash = described_class.to_hash(original)
      restored = described_class.from_hash(hash)
      expect(restored.id).to eq(original.id)
      expect(restored.content).to eq(original.content)
      expect(restored.scope).to eq(original.scope)
      expect(restored.tags).to eq(original.tags)
      expect(restored.confidence).to eq(original.confidence)
    end
  end
end
