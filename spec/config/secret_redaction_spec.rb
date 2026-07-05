# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Config::SecretRedaction do
  describe '.redact_secrets' do
    it 'returns non-string scalars unchanged' do
      expect(described_class.redact_secrets(42)).to eq(42)
      expect(described_class.redact_secrets(true)).to be(true)
      expect(described_class.redact_secrets(nil)).to be_nil
    end

    context 'with a Hash' do
      it 'redacts values whose key matches a secret pattern' do
        result = described_class.redact_secrets('api_key' => 'sk-12345', 'name' => 'hello')
        expect(result['api_key']).to eq('<redacted>')
        expect(result['name']).to eq('hello')
      end

      %w[authorization bearer client_secret password secret].each do |key|
        it "redacts '#{key}' key" do
          result = described_class.redact_secrets(key => 'abc')
          expect(result[key]).to eq('<redacted>')
        end
      end

      it 'redacts token key with underscores' do
        result = described_class.redact_secrets('auth_token' => 'abc')
        expect(result['auth_token']).to eq('<redacted>')
      end

      it 'recurses into nested hashes' do
        result = described_class.redact_secrets('config' => { 'api_key' => 'sk-999' })
        expect(result['config']['api_key']).to eq('<redacted>')
      end
    end

    context 'with an Array' do
      it 'recurses into each element' do
        input = [{ 'api_key' => 'sk-1' }, { 'name' => 'ok' }]
        result = described_class.redact_secrets(input)
        expect(result[0]['api_key']).to eq('<redacted>')
        expect(result[1]['name']).to eq('ok')
      end
    end

    context 'with a String' do
      it 'redacts bearer token in text' do
        expect(described_class.redact_secrets('Bearer eyJhbGciOiJIUzI1NiJ9')).to eq('Bearer <redacted>')
      end

      it 'redacts token= pattern' do
        expect(described_class.redact_secrets('token=secret123')).to eq('token=<redacted>')
      end

      it 'redacts api_key= pattern' do
        expect(described_class.redact_secrets('api_key=sk-abc123')).to eq('api_key=<redacted>')
      end

      it 'leaves plain strings unchanged' do
        msg = 'just a normal log message'
        expect(described_class.redact_secrets(msg)).to eq(msg)
      end
    end
  end
end
