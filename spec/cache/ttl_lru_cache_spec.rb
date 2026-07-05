# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TtlLruCache do
  subject(:cache) { described_class.new(limit: 3, ttl_ms: 1000, now: clock) }

  let(:now_ms) { 1_000_000 }
  let(:clock) { -> { now_ms } }

  describe '#initialize' do
    it 'raises ArgumentError for zero ttl_ms' do
      expect { described_class.new(limit: 3, ttl_ms: 0) }.to raise_error(ArgumentError)
    end
  end

  describe '#set and #get' do
    it 'stores and retrieves values' do
      cache.set(:a, 'val')
      expect(cache.get(:a)).to eq('val')
    end

    it 'returns nil for missing keys' do
      expect(cache.get(:missing)).to be_nil
    end
  end

  describe 'TTL expiration' do
    it 'returns nil for expired entries' do
      cache.set(:a, 'val')
      cache.instance_variable_set(:@now, -> { now_ms + 1001 })
      expect(cache.get(:a)).to be_nil
    end

    it 'returns value before expiration' do
      cache.set(:a, 'val')
      cache.instance_variable_set(:@now, -> { now_ms + 999 })
      expect(cache.get(:a)).to eq('val')
    end
  end

  describe '#set eviction' do
    it 'returns evicted value' do
      cache.set(:a, 'val_a')
      cache.set(:b, 'val_b')
      cache.set(:c, 'val_c')
      evicted = cache.set(:d, 'val_d')
      expect(evicted).to eq('val_a')
    end

    it 'returns nil when not at capacity' do
      expect(cache.set(:a, 'val')).to be_nil
    end
  end

  describe '#has?' do
    it 'returns true for existing non-expired keys' do
      cache.set(:a, 'val')
      expect(cache.has?(:a)).to be(true)
    end

    it 'returns false for expired keys' do
      cache.set(:a, 'val')
      cache.instance_variable_set(:@now, -> { now_ms + 1001 })
      expect(cache.has?(:a)).to be(false)
    end
  end

  describe '#delete' do
    it 'deletes an existing key' do
      cache.set(:a, 'val')
      cache.delete(:a)
      expect(cache.has?(:a)).to be(false)
    end
  end

  describe '#clear' do
    it 'empties the cache' do
      cache.set(:a, 'val')
      cache.clear
      expect(cache.size).to eq(0)
    end
  end

  describe '#sweep' do
    it 'returns 0 when no expired entries' do
      cache.set(:a, 'val')
      expect(cache.sweep).to eq(0)
    end
  end

  describe '#size' do
    it 'reports current size' do
      expect(cache.size).to eq(0)
      cache.set(:a, 1)
      expect(cache.size).to eq(1)
      cache.set(:b, 2)
      expect(cache.size).to eq(2)
    end
  end
end
