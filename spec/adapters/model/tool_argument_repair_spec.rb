# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/model/tool_argument_repair'

RSpec.describe DeepForge::Adapters::Model::ToolArgumentRepair do
  describe '.repair_tool_arguments' do
    it 'returns empty hash for empty string' do
      result = described_class.repair_tool_arguments('')
      expect(result).to eq(arguments: {}, repaired: false)
    end

    it 'returns empty hash for whitespace-only string' do
      result = described_class.repair_tool_arguments('   ')
      expect(result).to eq(arguments: {}, repaired: false)
    end

    it 'parses valid JSON object directly' do
      result = described_class.repair_tool_arguments('{"key": "value"}')
      expect(result).to eq(arguments: { 'key' => 'value' }, repaired: false)
    end

    it 'strips markdown code fence and parses' do
      input = '```json
{"key": "value"}
```'
      result = described_class.repair_tool_arguments(input)
      expect(result).to eq(arguments: { 'key' => 'value' }, repaired: true)
    end

    it 'strips javascript code fence and parses' do
      input = '```javascript
{"key": "value"}
```'
      result = described_class.repair_tool_arguments(input)
      expect(result).to eq(arguments: { 'key' => 'value' }, repaired: true)
    end

    it 'extracts first JSON object from surrounding text' do
      input = 'Here is the JSON: {"key": "value"} end'
      result = described_class.repair_tool_arguments(input)
      expect(result).to eq(arguments: { 'key' => 'value' }, repaired: true)
    end

    it 'extracts first JSON array from surrounding text' do
      input = 'Result: [1, 2, 3]'
      result = described_class.repair_tool_arguments(input)
      expect(result).to eq(arguments: { value: [1, 2, 3] }, repaired: true)
    end

    it 'returns raw input when nothing parseable' do
      result = described_class.repair_tool_arguments('not json at all')
      expect(result).to eq(arguments: { __raw: 'not json at all' }, repaired: false)
    end

    it 'handles nested JSON objects' do
      input = '{"outer": {"inner": "value"}}'
      result = described_class.repair_tool_arguments(input)
      expect(result[:arguments]).to eq({ 'outer' => { 'inner' => 'value' } })
      expect(result[:repaired]).to be false
    end

    it 'handles escaped strings in JSON' do
      input = '{"text": "hello \\"world\\""}'
      result = described_class.repair_tool_arguments(input)
      expect(result[:arguments]['text']).to eq('hello "world"')
    end
  end

  describe '.parse_object' do
    it 'returns hash for valid JSON object' do
      expect(described_class.parse_object('{"a": 1}')).to eq({ 'a' => 1 })
    end

    it 'returns nil for non-object JSON' do
      expect(described_class.parse_object('[1,2,3]')).to be_nil
    end

    it 'returns nil for invalid JSON' do
      expect(described_class.parse_object('not json')).to be_nil
    end
  end

  describe '.parse_any' do
    it 'returns ok: true with parsed value for valid JSON' do
      result = described_class.parse_any('{"a": 1}')
      expect(result).to eq(ok: true, value: { 'a' => 1 })
    end

    it 'returns ok: false for invalid JSON' do
      expect(described_class.parse_any('bad')).to eq(ok: false)
    end
  end

  describe '.value_to_arguments' do
    it 'returns hash as-is when it is a Hash' do
      expect(described_class.value_to_arguments({ 'a' => 1 })).to eq({ 'a' => 1 })
    end

    it 'wraps non-hash values' do
      expect(described_class.value_to_arguments([1, 2])).to eq({ value: [1, 2] })
    end

    it 'wraps string values' do
      expect(described_class.value_to_arguments('hello')).to eq({ value: 'hello' })
    end
  end

  describe '.strip_markdown_fence' do
    it 'removes json fence' do
      input = "```json\n{\"a\":1}\n```"
      expect(described_class.strip_markdown_fence(input)).to eq('{"a":1}')
    end

    it 'removes js fence' do
      input = "```js\n{\"a\":1}\n```"
      expect(described_class.strip_markdown_fence(input)).to eq('{"a":1}')
    end

    it 'returns original text when no fence' do
      expect(described_class.strip_markdown_fence('{"a":1}')).to eq('{"a":1}')
    end
  end

  describe '.extract_balanced' do
    it 'extracts balanced braces' do
      result = described_class.extract_balanced('prefix { "a": { "b": 1 } } suffix', '{', '}')
      expect(result).to eq('{ "a": { "b": 1 } }')
    end

    it 'returns nil when no matching close bracket' do
      result = described_class.extract_balanced('{ unclosed', '{', '}')
      expect(result).to be_nil
    end

    it 'handles strings containing brackets' do
      result = described_class.extract_balanced('{"key": "{nested}"}', '{', '}')
      expect(result).to eq('{"key": "{nested}"}')
    end
  end
end
