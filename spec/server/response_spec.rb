# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'

RSpec.describe DeepForge::Server do
  describe '.json_response' do
    it 'creates a JsonResponse with default status 200' do
      response = described_class.json_response({ message: 'ok' })
      expect(response).to be_a(DeepForge::Server::JsonResponse)
      expect(response.status).to eq(200)
    end

    it 'creates a JsonResponse with custom status' do
      response = described_class.json_response({ error: 'not found' }, 404)
      expect(response.status).to eq(404)
    end

    it 'sets content-type header to application/json' do
      response = described_class.json_response({})
      expect(response.headers['content-type']).to eq('application/json; charset=utf-8')
    end

    it 'serializes body to JSON string' do
      response = described_class.json_response({ key: 'value' })
      parsed = JSON.parse(response.body)
      expect(parsed['key']).to eq('value')
    end

    it 'handles nested hashes' do
      response = described_class.json_response({ a: { b: 'c' } })
      parsed = JSON.parse(response.body)
      expect(parsed['a']['b']).to eq('c')
    end

    it 'handles arrays' do
      response = described_class.json_response({ items: [1, 2, 3] })
      parsed = JSON.parse(response.body)
      expect(parsed['items']).to eq([1, 2, 3])
    end
  end
end
