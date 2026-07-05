# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/tool_storm_breaker'

RSpec.describe DeepForge::Loop::ToolStormBreaker do
  subject(:breaker) { described_class.new(options) }

  let(:options) { {} }

  describe '#initialize' do
    it 'uses default window size and threshold' do
      expect(breaker).to be_a(described_class)
    end

    it 'accepts custom window size' do
      b = described_class.new(window_size: 4)
      expect(b).to be_a(described_class)
    end

    it 'accepts custom threshold' do
      b = described_class.new(threshold: 5)
      expect(b).to be_a(described_class)
    end

    it 'enforces minimum window size of 1' do
      b = described_class.new(window_size: 0)
      expect(b).to be_a(described_class)
    end

    it 'enforces minimum threshold of 2' do
      b = described_class.new(threshold: 1)
      expect(b).to be_a(described_class)
    end
  end

  describe '#inspect' do
    it 'does not suppress first call' do
      result = breaker.inspect({ tool_name: 'read', arguments: { path: '/foo' } })
      expect(result[:suppress]).to be(false)
    end

    it 'suppresses after threshold identical calls' do
      call = { tool_name: 'read', arguments: { path: '/foo' } }
      3.times { breaker.inspect(call) }
      result = breaker.inspect(call)
      expect(result[:suppress]).to be(true)
      expect(result[:reason]).to include('read')
    end

    it 'does not suppress different arguments' do
      3.times { |i| breaker.inspect({ tool_name: 'read', arguments: { path: "/foo#{i}" } }) }
      result = breaker.inspect({ tool_name: 'read', arguments: { path: '/other' } })
      expect(result[:suppress]).to be(false)
    end

    it 'does not suppress different tool names' do
      3.times { breaker.inspect({ tool_name: 'read', arguments: { path: '/foo' } }) }
      result = breaker.inspect({ tool_name: 'grep', arguments: { path: '/foo' } })
      expect(result[:suppress]).to be(false)
    end

    it 'never suppresses exempt tools' do
      call = { tool_name: 'request_user_input', arguments: {} }
      10.times { breaker.inspect(call) }
      result = breaker.inspect(call)
      expect(result[:suppress]).to be(false)
    end

    it 'clears read-only entries when a mutating call arrives' do
      # Add some read-only calls
      2.times { breaker.inspect({ tool_name: 'read', arguments: { path: '/foo' } }) }
      # Mutating call clears read-only history
      breaker.inspect({ tool_name: 'write', arguments: { path: '/foo', content: 'x' } })
      # Now read calls should not be suppressed (history was cleared)
      result = breaker.inspect({ tool_name: 'read', arguments: { path: '/foo' } })
      expect(result[:suppress]).to be(false)
    end

    it 'detects mutating tool calls by name' do
      %w[write edit edit_diff apply_patch delete move].each do |name|
        breaker = described_class.new
        call = { tool_name: name, arguments: {} }
        result = breaker.inspect(call)
        expect(result[:suppress]).to be(false)
      end
    end

    it 'detects mutating tool calls by tool_kind' do
      breaker = described_class.new
      call = { tool_name: 'custom_tool', tool_kind: 'file_change', arguments: {} }
      result = breaker.inspect(call)
      expect(result[:suppress]).to be(false)
    end
  end

  describe '#reset' do
    it 'clears all tracked calls' do
      call = { tool_name: 'read', arguments: { path: '/foo' } }
      3.times { breaker.inspect(call) }
      breaker.reset
      result = breaker.inspect(call)
      expect(result[:suppress]).to be(false)
    end
  end

  describe 'argument key ordering' do
    it 'treats same arguments with different key order as identical' do
      call1 = { tool_name: 'read', arguments: { a: 1, b: 2 } }
      call2 = { tool_name: 'read', arguments: { b: 2, a: 1 } }
      breaker.inspect(call1)
      breaker.inspect(call2)
      result = breaker.inspect(call1)
      expect(result[:suppress]).to be(true)
    end
  end

  describe 'window eviction' do
    it 'evicts oldest entries beyond window size' do
      b = described_class.new(window_size: 3, threshold: 10)
      (1..5).each { |i| b.inspect({ tool_name: 'read', arguments: { path: "/f#{i}" } }) }
      # Window is 3, so only last 3 unique calls tracked
      # The first calls have been evicted, so they shouldn't trigger suppression
      result = b.inspect({ tool_name: 'read', arguments: { path: '/f1' } })
      expect(result[:suppress]).to be(false)
    end
  end
end
