# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/tool_call_repair'

RSpec.describe DeepForge::Loop::ToolCallRepair do
  describe '.repair' do
    it 'returns arguments unchanged when clean' do
      raw = { path: '/foo', content: 'bar' }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq(raw)
      expect(result[:notes]).to be_empty
    end

    it 'flattens arguments wrapper' do
      raw = { 'arguments' => { 'path' => '/foo' } }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'path' => '/foo' })
      expect(result[:notes]).to include('flattened arguments wrapper')
    end

    it 'flattens args wrapper' do
      raw = { 'args' => { 'path' => '/foo' } }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'path' => '/foo' })
      expect(result[:notes]).to include('flattened args wrapper')
    end

    it 'flattens input wrapper' do
      raw = { 'input' => { 'path' => '/foo' } }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'path' => '/foo' })
    end

    it 'flattens parameters wrapper' do
      raw = { 'parameters' => { 'path' => '/foo' } }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'path' => '/foo' })
    end

    it 'flattens when only wrapper key present' do
      raw = { 'arguments' => { 'a' => 1 } }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'a' => 1 })
    end

    it 'flattens with tool metadata keys present' do
      raw = { 'arguments' => { 'a' => 1 }, 'tool' => 'read' }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'a' => 1 })
    end

    it 'scavenges JSON string values' do
      raw = { data: '{"key":"value"}' }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'key' => 'value' })
      expect(result[:notes]).to include('scavenged JSON object from data')
    end

    it 'parses JSON from markdown fence' do
      raw = { data: '```json\n{"key":"value"}\n```' }
      result = described_class.repair(raw)
      expect(result[:arguments]).to eq({ 'key' => 'value' })
    end

    it 'truncates oversized strings' do
      raw = { content: 'a' * (600 * 1024) }
      result = described_class.repair(raw, max_string_bytes: 512 * 1024)
      expect(result[:arguments][:content]).to include('truncated')
      expect(result[:notes].any? { |n| n.include?('truncated') }).to be(true)
    end

    it 'preserves long strings for file_change tool kind' do
      raw = { content: 'a' * (600 * 1024) }
      result = described_class.repair(raw, tool_kind: 'file_change')
      expect(result[:arguments][:content].length).to eq(600 * 1024)
    end

    it 'does not truncate strings within limit' do
      raw = { content: 'short' }
      result = described_class.repair(raw, max_string_bytes: 512 * 1024)
      expect(result[:arguments][:content]).to eq('short')
    end
  end

  describe '.flatten_wrapper' do
    it 'returns nil when no wrapper key' do
      expect(described_class.flatten_wrapper({ 'a' => 1 })).to be_nil
    end

    it 'returns nil when multiple non-metadata keys' do
      expect(described_class.flatten_wrapper({ 'arguments' => { 'a' => 1 }, 'other' => 2 })).to be_nil
    end

    it 'returns parsed hash for valid wrapper' do
      result = described_class.flatten_wrapper({ 'arguments' => { 'a' => 1 } })
      expect(result).not_to be_nil
      expect(result[:arguments]).to eq({ 'a' => 1 })
    end
  end

  describe '.can_flatten_wrapper?' do
    it 'returns true for single key' do
      expect(described_class.can_flatten_wrapper?({ 'arguments' => {} }, 'arguments')).to be(true)
    end

    it 'returns true for wrapper + metadata keys' do
      expect(described_class.can_flatten_wrapper?(
               { 'arguments' => {}, 'tool' => 'read', 'callId' => 'c1' }, 'arguments'
             )).to be(true)
    end

    it 'returns false for multiple non-metadata keys' do
      expect(described_class.can_flatten_wrapper?(
               { 'arguments' => {}, 'custom' => 1 }, 'arguments'
             )).to be(false)
    end
  end

  describe '.scavenge_single_json_string' do
    it 'parses JSON from single string entry' do
      raw = { 'data' => '{"a":1}' }
      result = described_class.scavenge_single_json_string(raw)
      expect(result[:arguments]).to eq({ 'a' => 1 })
    end

    it 'returns nil for non-string value' do
      expect(described_class.scavenge_single_json_string({ 'data' => 123 })).to be_nil
    end

    it 'returns nil for multiple entries' do
      expect(described_class.scavenge_single_json_string({ 'a' => 1, 'b' => 2 })).to be_nil
    end

    it 'returns nil for invalid JSON' do
      expect(described_class.scavenge_single_json_string({ 'data' => 'not json' })).to be_nil
    end
  end

  describe '.parse_jsonish_object' do
    it 'parses plain JSON' do
      expect(described_class.parse_jsonish_object('{"a":1}')).to eq({ 'a' => 1 })
    end

    it 'parses JSON in markdown fence' do
      expect(described_class.parse_jsonish_object('```json\n{"a":1}\n```')).to eq({ 'a' => 1 })
    end

    it 'extracts JSON from surrounding text' do
      expect(described_class.parse_jsonish_object('prefix {"a":1} suffix')).to eq({ 'a' => 1 })
    end

    it 'returns nil for non-JSON' do
      expect(described_class.parse_jsonish_object('not json at all')).to be_nil
    end

    it 'returns nil for non-hash JSON' do
      expect(described_class.parse_jsonish_object('[1,2,3]')).to be_nil
    end
  end

  describe '.truncate_oversized_strings' do
    it 'truncates strings exceeding limit' do
      value = { content: 'a' * 1000 }
      result = described_class.truncate_oversized_strings(value, max_string_bytes: 100)
      expect(result[:changed]).to be(true)
      expect(result[:count]).to eq(1)
      expect(result[:value][:content]).to include('truncated')
    end

    it 'does not truncate when within limit' do
      value = { content: 'short' }
      result = described_class.truncate_oversized_strings(value, max_string_bytes: 1000)
      expect(result[:changed]).to be(false)
      expect(result[:count]).to eq(0)
    end

    it 'preserves long strings when option set' do
      value = { content: 'a' * 1000 }
      result = described_class.truncate_oversized_strings(value, {
                                                            max_string_bytes: 100,
                                                            preserve_long_strings: true
                                                          })
      expect(result[:changed]).to be(false)
    end

    it 'truncates nested strings' do
      value = { outer: { inner: 'a' * 1000 } }
      result = described_class.truncate_oversized_strings(value, max_string_bytes: 100)
      expect(result[:changed]).to be(true)
      expect(result[:value][:outer][:inner]).to include('truncated')
    end

    it 'truncates array elements' do
      value = { items: ['a' * 1000] }
      result = described_class.truncate_oversized_strings(value, max_string_bytes: 100)
      expect(result[:changed]).to be(true)
      expect(result[:value][:items][0]).to include('truncated')
    end
  end

  describe '.strip_markdown_fence' do
    it 'removes json fence' do
      expect(described_class.strip_markdown_fence("```json\n{ \"a\": 1 }\n```")).to eq('{ "a": 1 }')
    end

    it 'removes plain fence' do
      expect(described_class.strip_markdown_fence("```\n{ \"a\": 1 }\n```")).to eq('{ "a": 1 }')
    end

    it 'returns unchanged text when no fence' do
      expect(described_class.strip_markdown_fence('{"a":1}')).to eq('{"a":1}')
    end
  end

  describe '.extract_first_json_object' do
    it 'extracts JSON object from text' do
      result = described_class.extract_first_json_object('prefix {"a":1} suffix')
      expect(result).to eq('{"a":1}')
    end

    it 'handles nested braces' do
      result = described_class.extract_first_json_object('{"a":{"b":1}}')
      expect(result).to eq('{"a":{"b":1}}')
    end

    it 'returns nil when no opening brace' do
      expect(described_class.extract_first_json_object('no json')).to be_nil
    end

    it 'handles strings with braces' do
      result = described_class.extract_first_json_object('{"text":"{hello}"}')
      expect(result).to eq('{"text":"{hello}"}')
    end
  end

  describe '.slice_utf8' do
    it 'truncates to max bytes' do
      result = described_class.slice_utf8('hello world', 5)
      expect(result).to eq('hello')
    end

    it 'handles multi-byte characters' do
      result = described_class.slice_utf8('héllo', 4)
      expect(result.bytesize).to be <= 4
    end
  end
end
