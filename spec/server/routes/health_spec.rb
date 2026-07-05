# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/routes/health'

RSpec.describe DeepForge::Server::Routes do
  describe '.health_json_response' do
    it 'returns a JsonResponse with status 200' do
      response = described_class.health_json_response
      expect(response).to be_a(DeepForge::Server::JsonResponse)
      expect(response.status).to eq(200)
    end

    it 'returns ok status, service name, and mode' do
      response = described_class.health_json_response
      body = JSON.parse(response.body)
      expect(body['status']).to eq('ok')
      expect(body['service']).to eq('deepforge')
      expect(body['mode']).to eq('serve')
    end
  end
end
