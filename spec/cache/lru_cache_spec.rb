# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LruCache do
  describe '#initialize' do
    it 'raises ArgumentError for zero limit' do
      expect { described_class.new(0) }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError for negative limit' do
      expect { described_class.new(-1) }.to raise_error(ArgumentError)
    end

    it 'creates cache with given limit' do
      cache = described_class.new(5)
      expect(cache.limit).to eq(5)
      expect(cache.size).to eq(0)
    end
  end

  describe '#set and #get' do
    subject(:cache) { described_class.new(3) }

    it 'stores and retrieves values' do
      cache.set(:a, 1)
      expect(cache.get(:a)).to eq(1)
    end

    it 'returns nil for missing keys' do
      expect(cache.get(:missing)).to be_nil
    end

    it 'overwrites existing keys' do
      cache.set(:a, 1)
      cache.set(:a, 2)
      expect(cache.get(:a)).to eq(2)
      expect(cache.size).to eq(1)
    end
  end

  describe '#set eviction' do
    subject(:cache) { described_class.new(2) }

    it 'evicts oldest entry when capacity exceeded' do
      cache.set(:a, 1)
      cache.set(:b, 2)
      evicted = cache.set(:c, 3)
      expect(evicted).to eq(1)
      expect(cache.get(:b)).to eq(2)
      expect(cache.get(:c)).to eq(3)
    end

    it 'does not evict when updating existing key' do
      cache.set(:a, 1)
      cache.set(:b, 2)
      evicted = cache.set(:a, 10)
      expect(evicted).to be_nil
      expect(cache.size).to eq(2)
    end

    it 'returns nil when not at capacity' do
      evicted = cache.set(:a, 1)
      expect(evicted).to be_nil
    end
  end

  describe '#get LRU ordering' do
    subject(:cache) { described_class.new(3) }

    it 'promotes accessed key to most recent' do
      cache.set(:a, 1)
      cache.set(:b, 2)
      cache.set(:c, 3)
      cache.get(:a) # promote :a
      cache.set(:d, 4) # should evict :b (oldest)
      expect(cache.get(:a)).to eq(1)
      expect(cache.get(:d)).to eq(4)
    end
  end

  describe '#has?' do
    subject(:cache) { described_class.new(3) }

    it 'returns true for existing keys' do
      cache.set(:a, 1)
      expect(cache.has?(:a)).to be true
    end

    it 'returns false for missing keys' do
      expect(cache.has?(:a)).to be false
    end
  end

  describe '#delete' do
    it 'removes the key from the cache' do
      cache = described_class.new(3)
      cache.set(:a, 1)
      cache.delete(:a)
      expect(cache.has?(:a)).to be false
    end
  end

  describe '#clear' do
    it 'empties the cache' do
      cache = described_class.new(3)
      cache.set(:a, 1)
      cache.set(:b, 2)
      cache.clear
      expect(cache.size).to eq(0)
      expect(cache.get(:a)).to be_nil
    end
  end

  describe '#keys and #values' do
    subject(:cache) { described_class.new(3) }

    it 'returns keys in order' do
      cache.set(:a, 1)
      cache.set(:b, 2)
      expect(cache.keys).to eq(%i[a b])
      expect(cache.values).to eq([1, 2])
    end
  end
end
