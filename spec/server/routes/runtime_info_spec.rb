# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/routes/runtime_info'

RSpec.describe DeepForge::Server::Routes do
  describe '.runtime_info_json_response' do
    it 'returns runtime info from the info lambda' do
      runtime = {
        info: -> { { host: '127.0.0.1', port: 8899, model: 'deepseek-chat' } }
      }

      response = described_class.runtime_info_json_response(runtime)
      body = JSON.parse(response.body)
      expect(body['host']).to eq('127.0.0.1')
      expect(body['port']).to eq(8899)
      expect(body['model']).to eq('deepseek-chat')
    end
  end

  describe '.redact_secrets' do
    it 'redacts keys containing "key"' do
      data = { api_key: 'sk-abc123def456', name: 'test' }
      result = described_class.redact_secrets(data)
      expect(result[:api_key]).to eq('sk-a****')
      expect(result[:name]).to eq('test')
    end

    it 'redacts keys containing "token"' do
      data = { auth_token: 'tok12345' }
      result = described_class.redact_secrets(data)
      expect(result[:auth_token]).to eq('tok1****')
    end

    it 'redacts keys containing "secret"' do
      data = { client_secret: 'secret123' }
      result = described_class.redact_secrets(data)
      expect(result[:client_secret]).to eq('secr****')
    end

    it 'shows **** for short values' do
      data = { api_key: 'ab' }
      result = described_class.redact_secrets(data)
      expect(result[:api_key]).to eq('****')
    end

    it 'recursively redacts nested hashes' do
      data = { config: { api_key: 'sk-long-key-here' } }
      result = described_class.redact_secrets(data)
      expect(result[:config][:api_key]).to eq('sk-l****')
    end

    it 'redacts within arrays of hashes' do
      data = { servers: [{ api_key: 'sk-abc123' }] }
      result = described_class.redact_secrets(data)
      expect(result[:servers].first[:api_key]).to eq('sk-a****')
    end

    it 'leaves non-matching string keys unchanged' do
      data = { username: 'alice', host: 'localhost' }
      result = described_class.redact_secrets(data)
      expect(result[:username]).to eq('alice')
      expect(result[:host]).to eq('localhost')
    end

    it 'returns non-hash data unchanged' do
      expect(described_class.redact_secrets('string')).to eq('string')
      expect(described_class.redact_secrets(42)).to eq(42)
    end
  end
end
