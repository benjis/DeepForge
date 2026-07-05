# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Utils::KeyNormalizer do
  describe '.to_snake' do
    it 'converts PascalCase to snake_case' do
      expect(described_class.to_snake('PascalCase')).to eq(:pascal_case)
    end

    it 'converts camelCase to snake_case' do
      expect(described_class.to_snake('camelCase')).to eq(:camel_case)
    end

    it 'converts consecutive uppercase to snake_case' do
      expect(described_class.to_snake('XMLParser')).to eq(:xml_parser)
    end

    it 'handles already_snake_case' do
      expect(described_class.to_snake('already_snake')).to eq(:already_snake)
    end

    it 'converts hyphens to underscores' do
      expect(described_class.to_snake('kebab-case')).to eq(:kebab_case)
    end

    it 'converts :: to / in result' do
      expect(described_class.to_snake('Foo::Bar')).to eq(:'foo/bar')
    end

    it 'returns a symbol' do
      expect(described_class.to_snake('test')).to be_a(Symbol)
    end
  end

  describe '.to_camel' do
    it 'converts snake_case to camelCase' do
      expect(described_class.to_camel(:snake_case)).to eq(:snakeCase)
    end

    it 'returns single-word keys unchanged' do
      expect(described_class.to_camel(:word)).to eq(:word)
    end

    it 'handles multi-part snake_case' do
      expect(described_class.to_camel(:one_two_three)).to eq(:oneTwoThree)
    end
  end

  describe '.transform_keys' do
    it 'applies converter to all keys' do
      hash = { 'foo_bar' => 1, 'baz' => 2 }
      result = described_class.transform_keys(hash) { |k| k.to_s.upcase }
      expect(result).to eq('FOO_BAR' => 1, 'BAZ' => 2)
    end

    it 'recursively transforms nested hash keys' do
      hash = { 'outer' => { 'inner_key' => 'val' } }
      result = described_class.transform_keys(hash) { |k| k.to_s.upcase }
      expect(result).to eq('OUTER' => { 'INNER_KEY' => 'val' })
    end

    it 'does not transform non-hash values' do
      hash = { 'key' => [1, 2, { 'nested' => 3 }] }
      result = described_class.transform_keys(hash) { |k| k.to_s.upcase }
      expect(result['KEY']).to eq([1, 2, { 'nested' => 3 }])
    end
  end

  describe '.snakify_keys' do
    it 'converts all keys to snake_case' do
      hash = { 'camelCase' => 1, 'PascalCase' => 2 }
      result = described_class.snakify_keys(hash)
      expect(result).to eq(camel_case: 1, pascal_case: 2)
    end

    it 'recursively converts nested keys' do
      hash = { 'outerKey' => { 'innerKey' => 'val' } }
      result = described_class.snakify_keys(hash)
      expect(result).to eq(outer_key: { inner_key: 'val' })
    end
  end

  describe '.camelize_keys' do
    it 'converts all keys to camelCase' do
      hash = { 'some_key' => 1, 'another_key' => 2 }
      result = described_class.camelize_keys(hash)
      expect(result).to eq(someKey: 1, anotherKey: 2)
    end

    it 'recursively converts nested keys' do
      hash = { 'outer_key' => { 'inner_key' => 'val' } }
      result = described_class.camelize_keys(hash)
      expect(result).to eq(outerKey: { innerKey: 'val' })
    end
  end
end
