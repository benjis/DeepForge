# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/routes/workspace'

RSpec.describe DeepForge::Server::Routes do
  describe '.build_workspace_status_response' do
    it 'returns default response when path is nil' do
      response = described_class.build_workspace_status_response(inspector: nil, path: nil)
      expect(response).to be_a(DeepForge::Server::JsonResponse)
      body = JSON.parse(response.body)
      expect(body['exists']).to be false
      expect(body['isGitRepository']).to be false
    end

    it 'queries inspector when path is provided' do
      inspector = double('Store')
      allow(inspector).to receive(:status).with('/workspace').and_return({
                                                                           path: '/workspace',
                                                                           exists: true,
                                                                           isGitRepository: true,
                                                                           branch: 'main'
                                                                         })

      response = described_class.build_workspace_status_response(inspector: inspector, path: '/workspace')
      body = JSON.parse(response.body)
      expect(body['exists']).to be true
      expect(body['isGitRepository']).to be true
    end
  end
end
