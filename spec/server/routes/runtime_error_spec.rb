# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/routes/runtime_error'

RSpec.describe DeepForge::Server::Routes do
  describe '.error_response' do
    it 'creates a JsonResponse with given status' do
      response = described_class.error_response({ code: 'test', message: 'error' }, 418)
      expect(response).to be_a(DeepForge::Server::JsonResponse)
      expect(response.status).to eq(418)
    end

    it 'serializes the body to JSON' do
      response = described_class.error_response({ code: 'err', message: 'msg' }, 500)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('err')
      expect(body['message']).to eq('msg')
    end
  end

  describe 'ERRORS' do
    it 'defines unauthorized error (401)' do
      response = described_class::ERRORS[:unauthorized].call('custom msg')
      expect(response.status).to eq(401)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('unauthorized')
      expect(body['message']).to eq('custom msg')
    end

    it 'defaults unauthorized message' do
      response = described_class::ERRORS[:unauthorized].call
      body = JSON.parse(response.body)
      expect(body['message']).to eq('unauthorized')
    end

    it 'defines forbidden error (403)' do
      response = described_class::ERRORS[:forbidden].call
      expect(response.status).to eq(403)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('forbidden')
    end

    it 'defines not_found error (404)' do
      response = described_class::ERRORS[:not_found].call('gone')
      expect(response.status).to eq(404)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('not_found')
      expect(body['message']).to eq('gone')
    end

    it 'defines validation error (400)' do
      response = described_class::ERRORS[:validation].call('bad input')
      expect(response.status).to eq(400)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('validation_error')
    end

    it 'defines validation error with issues' do
      response = described_class::ERRORS[:validation].call('bad', %w[issue1 issue2])
      body = JSON.parse(response.body)
      expect(body['details']).to eq(%w[issue1 issue2])
    end

    it 'defines conflict error (409)' do
      response = described_class::ERRORS[:conflict].call('conflict msg')
      expect(response.status).to eq(409)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('conflict')
    end

    it 'defines unavailable error (503)' do
      response = described_class::ERRORS[:unavailable].call('offline')
      expect(response.status).to eq(503)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('capability_unavailable')
    end

    it 'defines internal error (500)' do
      response = described_class::ERRORS[:internal].call('crash')
      expect(response.status).to eq(500)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('internal_error')
    end
  end
end
