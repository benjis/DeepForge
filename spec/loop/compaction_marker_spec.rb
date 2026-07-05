# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/compaction/marker'

RSpec.describe DeepForge::Loop::CompactionMarker do
  describe '.compute_short_hash' do
    it 'returns a hex string of specified length' do
      hash = described_class.compute_short_hash('hello world', 16)
      expect(hash.length).to eq(16)
      expect(hash).to match(/\A[0-9a-f]+\z/)
    end

    it 'returns different hashes for different inputs' do
      h1 = described_class.compute_short_hash('hello')
      h2 = described_class.compute_short_hash('world')
      expect(h1).not_to eq(h2)
    end

    it 'returns consistent hashes for same input' do
      h1 = described_class.compute_short_hash('test')
      h2 = described_class.compute_short_hash('test')
      expect(h1).to eq(h2)
    end

    it 'defaults to length 16' do
      hash = described_class.compute_short_hash('test')
      expect(hash.length).to eq(16)
    end
  end

  describe '.create_tool_digest_marker' do
    it 'creates a marker with the hash' do
      marker = described_class.create_tool_digest_marker('abc123')
      expect(marker).to include('abc123')
      expect(marker).to start_with('<deepforge:tool_digest')
    end

    it 'escapes special characters in hash' do
      marker = described_class.create_tool_digest_marker('a&b"c')
      expect(marker).to include('a&amp;b&quot;c')
    end
  end

  describe '.compacted_items_digest_source' do
    it 'produces a stable JSON string' do
      items = [
        { kind: 'user_message', text: 'hello' },
        { kind: 'assistant_text', text: 'world' }
      ]
      s1 = described_class.compacted_items_digest_source(items)
      s2 = described_class.compacted_items_digest_source(items)
      expect(s1).to eq(s2)
    end

    it 'produces different output for different items' do
      items1 = [{ kind: 'user_message', text: 'hello' }]
      items2 = [{ kind: 'user_message', text: 'world' }]
      expect(described_class.compacted_items_digest_source(items1)).not_to eq(
        described_class.compacted_items_digest_source(items2)
      )
    end
  end

  describe '.compaction_digest_shape' do
    it 'returns nil for unknown kind' do
      expect(described_class.compaction_digest_shape({ kind: 'unknown' })).to be_nil
    end

    it 'shapes user_message' do
      result = described_class.compaction_digest_shape({ kind: 'user_message', text: 'hi' })
      expect(result).to eq({ kind: 'user_message', text: 'hi' })
    end

    it 'shapes tool_call with stable keys' do
      result = described_class.compaction_digest_shape({
                                                         kind: 'tool_call', call_id: 'c1', tool_name: 'read',
                                                         arguments: { b: 2, a: 1 }
                                                       })
      expect(result[:kind]).to eq('tool_call')
      expect(result[:arguments]).to eq({ a: 1, b: 2 })
    end

    it 'shapes tool_result' do
      result = described_class.compaction_digest_shape({
                                                         kind: 'tool_result', call_id: 'c1', tool_name: 'read',
                                                         output: 'result', is_error: false
                                                       })
      expect(result[:output]).to eq('result')
    end

    it 'shapes compaction' do
      result = described_class.compaction_digest_shape({
                                                         kind: 'compaction', summary: 's', replaced_tokens: 100
                                                       })
      expect(result[:summary]).to eq('s')
    end

    it 'shapes error' do
      result = described_class.compaction_digest_shape({
                                                         kind: 'error', message: 'err', code: 'E001'
                                                       })
      expect(result[:message]).to eq('err')
    end
  end

  describe '.stable_shape' do
    it 'recursively sorts hash keys' do
      result = described_class.stable_shape({ b: 2, a: 1 })
      expect(result.keys).to eq(%i[a b])
    end

    it 'handles nested hashes' do
      result = described_class.stable_shape({ z: { b: 2, a: 1 } })
      expect(result[:z].keys).to eq(%i[a b])
    end

    it 'handles arrays' do
      result = described_class.stable_shape([{ b: 1, a: 2 }])
      expect(result[0].keys).to eq(%i[a b])
    end

    it 'passes through non-hash/array values' do
      expect(described_class.stable_shape('hello')).to eq('hello')
      expect(described_class.stable_shape(42)).to eq(42)
    end
  end

  describe '.escape_marker_attribute' do
    it 'escapes ampersand' do
      expect(described_class.escape_marker_attribute('a&b')).to eq('a&amp;b')
    end

    it 'escapes quotes' do
      expect(described_class.escape_marker_attribute('a"b')).to eq('a&quot;b')
    end
  end
end
