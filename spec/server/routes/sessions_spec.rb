# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'
require 'deepforge/server/routes/runtime_error'
require 'deepforge/server/routes/sessions'

RSpec.describe DeepForge::Server::Routes::Sessions do
  let(:thread_service) { double('ThreadService') }

  describe '.resume_session' do
    it 'resumes a session and returns thread info' do
      result = {
        thread: { id: 't1', title: 'Resumed session' },
        sessionId: 's1',
        messageCount: 5
      }
      allow(thread_service).to receive(:resume_session).and_return(result)

      request = { body: '{}' }
      response = described_class.resume_session(thread_service, 's1', request)
      expect(response.status).to eq(201)
      body = JSON.parse(response.body)
      expect(body['threadId']).to eq('t1')
      expect(body['sessionId']).to eq('s1')
    end

    it 'returns validation error for invalid body' do
      request = { body: 'not json' }
      response = described_class.resume_session(thread_service, 's1', request)
      expect(response.status).to eq(400)
    end

    it 'returns 404 on not found error' do
      allow(thread_service).to receive(:resume_session).and_raise(StandardError, 'session not found')

      request = { body: '{}' }
      response = described_class.resume_session(thread_service, 'missing', request)
      expect(response.status).to eq(404)
    end
  end
end
