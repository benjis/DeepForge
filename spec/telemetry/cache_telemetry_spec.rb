# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Telemetry::CacheTelemetry do
  subject(:telemetry) { described_class.new }

  describe '#record_hit / #record_miss / #record_write / #record_invalidation' do
    it 'accumulates per-thread counters' do
      telemetry.record_hit('t1', 100)
      telemetry.record_hit('t1', 50)
      telemetry.record_hit('t2', 30)
      telemetry.record_miss('t1', 200)
      telemetry.record_miss('t1', 100)
      telemetry.record_write('t1', 500)
      telemetry.record_invalidation('t1')
      telemetry.record_invalidation('t1')

      snap = telemetry.snapshot('t1')
      expect(snap[:hits]).to eq(150)
      expect(snap[:misses]).to eq(300)
      expect(snap[:writes]).to eq(500)
      expect(snap[:invalidations]).to eq(2)
      expect(telemetry.snapshot('t2')[:hits]).to eq(30)
    end
  end

  describe '#ingest' do
    it 'records hit and miss tokens from a usage snapshot' do
      snapshot = Struct.new(:cache_hit_tokens, :cache_miss_tokens, :cached_tokens).new(100, 50, 150)
      telemetry.ingest('t1', snapshot)

      snap = telemetry.snapshot('t1')
      expect(snap[:hits]).to eq(100)
      expect(snap[:misses]).to eq(50)
    end

    it 'records write tokens when cached_tokens exceeds hit tokens' do
      snapshot = Struct.new(:cache_hit_tokens, :cache_miss_tokens, :cached_tokens).new(30, 20, 100)
      telemetry.ingest('t1', snapshot)
      expect(telemetry.snapshot('t1')[:writes]).to eq(70)
    end

    it 'does not record writes when cached_tokens equals hit tokens' do
      snapshot = Struct.new(:cache_hit_tokens, :cache_miss_tokens, :cached_tokens).new(50, 50, 50)
      telemetry.ingest('t1', snapshot)
      expect(telemetry.snapshot('t1')[:writes]).to eq(0)
    end

    it 'handles nil cache_hit_tokens' do
      snapshot = Struct.new(:cache_hit_tokens, :cache_miss_tokens, :cached_tokens).new(nil, 20, 60)
      telemetry.ingest('t1', snapshot)
      snap = telemetry.snapshot('t1')
      expect(snap[:hits]).to eq(0)
      expect(snap[:writes]).to eq(60)
    end
  end

  describe '#snapshot' do
    it 'returns zeros and nil hit_rate for unknown thread' do
      snap = telemetry.snapshot('nonexistent')
      expect(snap[:hits]).to eq(0)
      expect(snap[:misses]).to eq(0)
      expect(snap[:writes]).to eq(0)
      expect(snap[:invalidations]).to eq(0)
      expect(snap[:hit_rate]).to be_nil
    end

    it 'computes hit_rate correctly' do
      telemetry.record_hit('t1', 75)
      telemetry.record_miss('t1', 25)
      expect(telemetry.snapshot('t1')[:hit_rate]).to eq(0.75)
    end

    it 'returns nil hit_rate when total is zero' do
      telemetry.record_write('t1', 100)
      expect(telemetry.snapshot('t1')[:hit_rate]).to be_nil
    end
  end

  describe '#reset' do
    it 'resets all data without arguments' do
      telemetry.record_hit('t1', 100)
      telemetry.record_miss('t2', 50)
      telemetry.reset
      expect(telemetry.snapshot('t1')[:hits]).to eq(0)
      expect(telemetry.snapshot('t2')[:misses]).to eq(0)
    end

    it 'resets only the specified thread' do
      telemetry.record_hit('t1', 100)
      telemetry.record_hit('t2', 200)
      telemetry.reset('t1')
      expect(telemetry.snapshot('t1')[:hits]).to eq(0)
      expect(telemetry.snapshot('t2')[:hits]).to eq(200)
    end
  end
end
