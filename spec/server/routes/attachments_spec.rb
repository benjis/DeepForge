# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'
require 'deepforge/server/routes/runtime_error'
require 'deepforge/server/routes/attachments'

RSpec.describe DeepForge::Server::Routes::Attachments do
  describe '.upload_attachment' do
    it 'returns unavailable when store is nil' do
      response = described_class.upload_attachment(nil, { body: '{}' })
      expect(response.status).to eq(503)
    end

    it 'returns validation error when name is missing' do
      store = double('AttachmentStore')
      request = { body: '{"dataBase64":"dGVzdA=="}' }
      response = described_class.upload_attachment(store, request)
      expect(response.status).to eq(400)
    end

    it 'returns validation error when dataBase64 is missing' do
      store = double('AttachmentStore')
      request = { body: '{"name":"file.txt"}' }
      response = described_class.upload_attachment(store, request)
      expect(response.status).to eq(400)
    end

    it 'returns validation error for invalid JSON' do
      store = double('AttachmentStore')
      request = { body: 'not json' }
      response = described_class.upload_attachment(store, request)
      expect(response.status).to eq(400)
    end
  end

  describe '.get_attachment_metadata' do
    it 'returns unavailable when store is nil' do
      response = described_class.get_attachment_metadata(nil, 'att_1')
      expect(response.status).to eq(503)
    end

    it 'returns 404 when attachment not found' do
      store = double('AttachmentStore')
      allow(store).to receive(:get).with('missing').and_return(nil)

      response = described_class.get_attachment_metadata(store, 'missing')
      expect(response.status).to eq(404)
    end

    it 'returns attachment metadata' do
      store = double('AttachmentStore')
      allow(store).to receive(:get).with('att_1').and_return({ id: 'att_1', name: 'f.txt' })

      response = described_class.get_attachment_metadata(store, 'att_1')
      body = JSON.parse(response.body)
      expect(body['attachment']['id']).to eq('att_1')
    end
  end

  describe '.attachment_diagnostics' do
    it 'returns disabled diagnostics when store is nil' do
      response = described_class.attachment_diagnostics(nil)
      body = JSON.parse(response.body)
      expect(body['enabled']).to be false
    end

    it 'returns store diagnostics when store exists' do
      store = double('AttachmentStore')
      allow(store).to receive(:diagnostics).and_return({ enabled: true, count: 5 })

      response = described_class.attachment_diagnostics(store)
      body = JSON.parse(response.body)
      expect(body['enabled']).to be true
      expect(body['count']).to eq(5)
    end
  end
end
