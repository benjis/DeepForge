# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'MemoryScope constants' do
    it 'defines USER, WORKSPACE, PROJECT' do
      expect(described_class::MemoryScope::USER).to eq('user')
      expect(described_class::MemoryScope::WORKSPACE).to eq('workspace')
      expect(described_class::MemoryScope::PROJECT).to eq('project')
    end
  end

  describe 'MemoryRecord' do
    it 'creates with keyword init' do
      record = described_class::MemoryRecord.new(
        id: 'm1', content: 'remember this', scope: 'workspace',
        tags: ['important'], confidence: 0.9
      )
      expect(record.id).to eq('m1')
      expect(record.content).to eq('remember this')
      expect(record.confidence).to eq(0.9)
    end
  end

  describe 'MemoryCreateRequest' do
    it 'creates with keyword init' do
      req = described_class::MemoryCreateRequest.new(
        content: 'test memory', scope: 'user', tags: ['test']
      )
      expect(req.content).to eq('test memory')
    end
  end

  describe 'MemoryUpdateRequest' do
    it 'creates with keyword init' do
      req = described_class::MemoryUpdateRequest.new(content: 'updated', disabled: true)
      expect(req.disabled).to be(true)
    end
  end

  describe 'MemoryDiagnostics' do
    it 'creates with keyword init' do
      diag = described_class::MemoryDiagnostics.new(
        enabled: true, root_dir: '/tmp', active_count: 5, tombstone_count: 2
      )
      expect(diag.active_count).to eq(5)
    end
  end
end
