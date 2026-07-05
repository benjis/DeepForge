# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'

RSpec.describe DeepForge::Server do
  describe '.read_json_body' do
    it 'returns ok with empty hash for nil body' do
      result = described_class.read_json_body(nil)
      expect(result.ok).to be true
      expect(result.value).to eq({})
      expect(result.response).to be_nil
    end

    it 'returns ok with empty hash for empty string body' do
      result = described_class.read_json_body('')
      expect(result.ok).to be true
      expect(result.value).to eq({})
      expect(result.response).to be_nil
    end

    it 'parses valid JSON and symbolizes keys' do
      result = described_class.read_json_body('{"name":"test","count":5}')
      expect(result.ok).to be true
      expect(result.value).to eq({ name: 'test', count: 5 })
    end

    it 'returns error response for invalid JSON' do
      result = described_class.read_json_body('not json')
      expect(result.ok).to be false
      expect(result.value).to be_nil
      expect(result.response).to be_a(DeepForge::Server::JsonResponse)
      expect(result.response.status).to eq(400)
    end

    it 'handles nested objects with key symbolization' do
      json = '{"user":{"name":"alice","age":30}}'
      result = described_class.read_json_body(json)
      expect(result.ok).to be true
      expect(result.value[:user][:name]).to eq('alice')
      expect(result.value[:user][:age]).to eq(30)
    end

    it 'handles arrays within JSON' do
      json = '{"items":["a","b","c"]}'
      result = described_class.read_json_body(json)
      expect(result.ok).to be true
      expect(result.value[:items]).to eq(%w[a b c])
    end
  end

  describe '.symbolize_keys' do
    it 'converts string keys to symbols in a hash' do
      result = described_class.symbolize_keys({ 'a' => 1, 'b' => 2 })
      expect(result).to eq({ a: 1, b: 2 })
    end

    it 'recursively converts nested hashes' do
      result = described_class.symbolize_keys({ 'outer' => { 'inner' => 'value' } })
      expect(result).to eq({ outer: { inner: 'value' } })
    end

    it 'handles arrays of hashes' do
      result = described_class.symbolize_keys([{ 'a' => 1 }, { 'b' => 2 }])
      expect(result).to eq([{ a: 1 }, { b: 2 }])
    end

    it 'passes through non-hash values unchanged' do
      expect(described_class.symbolize_keys('string')).to eq('string')
      expect(described_class.symbolize_keys(42)).to eq(42)
      expect(described_class.symbolize_keys(nil)).to be_nil
    end
  end
end
