# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PrefixVolatility do
  describe '.volatile_token_kind' do
    it 'identifies UUIDs' do
      expect(described_class.volatile_token_kind('550e8400-e29b-41d4-a716-446655440000')).to eq('uuid')
    end

    it 'identifies hex hashes' do
      md5 = 'd41d8cd98f00b204e9800998ecf8427e'
      expect(described_class.volatile_token_kind(md5)).to eq('hex_hash')
    end

    it 'identifies JWTs' do
      header = Base64.urlsafe_encode64('{"alg":"HS256"}', padding: false)
      payload = Base64.urlsafe_encode64('{"sub":"1"}', padding: false)
      sig = Base64.urlsafe_encode64('fake', padding: false)
      jwt = "#{header}.#{payload}.#{sig}"
      expect(described_class.volatile_token_kind(jwt)).to eq('jwt')
    end

    it 'returns nil for regular text' do
      expect(described_class.volatile_token_kind('hello')).to be_nil
      expect(described_class.volatile_token_kind('123')).to be_nil
    end
  end

  describe '.canonical_uuid?' do
    it 'returns true for valid UUID' do
      expect(described_class.canonical_uuid?('550e8400-e29b-41d4-a716-446655440000')).to be true
    end

    it 'returns false for short strings' do
      expect(described_class.canonical_uuid?('abc')).to be false
    end

    it 'returns false for wrong segment lengths' do
      expect(described_class.canonical_uuid?('550e8400-e29b-41d4-a716-44665544000')).to be false
    end
  end

  describe '.hex_hash?' do
    it 'returns true for MD5 length hex' do
      expect(described_class.hex_hash?('d41d8cd98f00b204e9800998ecf8427e')).to be true
    end

    it 'returns false for non-hex chars' do
      expect(described_class.hex_hash?('zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz')).to be false
    end

    it 'returns false for wrong length' do
      expect(described_class.hex_hash?('abc123')).to be false
    end
  end

  describe '.split_tokens' do
    it 'splits on whitespace' do
      expect(described_class.split_tokens('hello world')).to eq(%w[hello world])
    end

    it 'handles multiple spaces' do
      expect(described_class.split_tokens('a  b   c')).to eq(%w[a b c])
    end

    it 'handles leading/trailing spaces' do
      expect(described_class.split_tokens('  hello  ')).to eq(['hello'])
    end
  end

  describe '.strip_boundary_punctuation' do
    it 'strips leading/trailing punctuation' do
      expect(described_class.strip_boundary_punctuation('"hello,"')).to eq('hello')
    end

    it 'returns unchanged for no boundary punctuation' do
      expect(described_class.strip_boundary_punctuation('hello')).to eq('hello')
    end
  end

  describe '.detect_volatile_prefix_content' do
    it 'returns empty array for clean content' do
      prefix = ImmutablePrefixBuilder.create(system_prompt: 'You are helpful')
      findings = described_class.detect_volatile_prefix_content(prefix)
      expect(findings).to eq([])
    end

    it 'detects UUIDs in system prompt' do
      prefix = ImmutablePrefixBuilder.create(
        system_prompt: 'User id: 550e8400-e29b-41d4-a716-446655440000'
      )
      findings = described_class.detect_volatile_prefix_content(prefix)
      expect(findings.size).to eq(1)
      expect(findings.first[:kind]).to eq('uuid')
      expect(findings.first[:field]).to eq('systemPrompt')
    end

    it 'detects hex hashes in system prompt' do
      prefix = ImmutablePrefixBuilder.create(
        system_prompt: 'SHA: d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592'
      )
      findings = described_class.detect_volatile_prefix_content(prefix)
      hash_findings = findings.select { |f| f[:kind] == 'hex_hash' }
      expect(hash_findings.size).to eq(1)
    end
  end
end
