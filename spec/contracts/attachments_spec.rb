# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'AttachmentTextFallback' do
    it 'creates with keyword init' do
      fb = described_class::AttachmentTextFallback.new(
        data_base64: 'abc', mime_type: 'image/webp',
        byte_size: 1024, width: 800, height: 600, was_compressed: true
      )
      expect(fb.data_base64).to eq('abc')
      expect(fb.was_compressed).to be(true)
    end
  end

  describe 'AttachmentMetadata' do
    it 'creates with all fields' do
      meta = described_class::AttachmentMetadata.new(
        id: 'a1', name: 'pic.png', mime_type: 'image/png',
        byte_size: 2048, hash: 'abc123', width: 100, height: 100
      )
      expect(meta.id).to eq('a1')
      expect(meta.byte_size).to eq(2048)
    end
  end

  describe 'AttachmentUploadRequest' do
    it 'creates with keyword init' do
      req = described_class::AttachmentUploadRequest.new(
        name: 'file.txt', mime_type: 'text/plain', data_base64: 'aGVsbG8='
      )
      expect(req.name).to eq('file.txt')
    end
  end

  describe 'AttachmentUploadResponse' do
    it 'creates with attachment' do
      resp = described_class::AttachmentUploadResponse.new(attachment: { id: 'a1' })
      expect(resp.attachment[:id]).to eq('a1')
    end
  end

  describe 'AttachmentDiagnostics' do
    it 'creates with diagnostic fields' do
      diag = described_class::AttachmentDiagnostics.new(enabled: true, root_dir: '/tmp', count: 5, total_bytes: 1024)
      expect(diag.enabled).to be(true)
      expect(diag.count).to eq(5)
    end
  end
end
