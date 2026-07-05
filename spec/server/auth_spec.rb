# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/middleware/auth'

RSpec.describe DeepForge::Server do
  describe '.bearer_token' do
    it 'extracts bearer token from authorization header' do
      headers = { 'authorization' => 'Bearer abc123' }
      expect(described_class.bearer_token(headers)).to eq('abc123')
    end

    it 'is case insensitive for Bearer prefix' do
      headers = { 'authorization' => 'bearer abc123' }
      expect(described_class.bearer_token(headers)).to eq('abc123')

      headers = { 'authorization' => 'BEARER abc123' }
      expect(described_class.bearer_token(headers)).to eq('abc123')
    end

    it 'returns nil when authorization header is missing' do
      expect(described_class.bearer_token({})).to be_nil
    end

    it 'returns nil when authorization header does not match Bearer pattern' do
      headers = { 'authorization' => 'Basic abc123' }
      expect(described_class.bearer_token(headers)).to be_nil
    end

    it 'handles tokens with spaces' do
      headers = { 'authorization' => 'Bearer token with spaces' }
      expect(described_class.bearer_token(headers)).to eq('token with spaces')
    end
  end

  describe '.authorized?' do
    let(:token) { 'secret-token-123' }

    it 'returns true when insecure mode is enabled' do
      headers = {}
      expect(described_class.authorized?(headers, token, true)).to be true
    end

    it 'returns true when bearer token matches expected token' do
      headers = { 'authorization' => "Bearer #{token}" }
      expect(described_class.authorized?(headers, token)).to be true
    end

    it 'returns false when bearer token does not match' do
      headers = { 'authorization' => 'Bearer wrong-token' }
      expect(described_class.authorized?(headers, token)).to be false
    end

    it 'returns false when no authorization header present' do
      expect(described_class.authorized?({}, token)).to be false
    end

    it 'returns false when expected token is empty' do
      headers = { 'authorization' => 'Bearer something' }
      expect(described_class.authorized?(headers, '')).to be false
    end

    it 'defaults insecure to false' do
      headers = {}
      expect(described_class.authorized?(headers, token)).to be false
    end
  end
end
