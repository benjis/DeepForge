# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/auto_model_router'

RSpec.describe DeepForge::Loop::AutoModelRouter do
  describe '::AUTO_MODEL_FLASH' do
    it 'is deepseek-v4-flash' do
      expect(described_class::AUTO_MODEL_FLASH).to eq('deepseek-v4-flash')
    end
  end

  describe '::AUTO_MODEL_PRO' do
    it 'is deepseek-v4-pro' do
      expect(described_class::AUTO_MODEL_PRO).to eq('deepseek-v4-pro')
    end
  end

  describe '.heuristic' do
    it 'returns pro for complex keywords' do
      %w[refactor architecture design debug security review audit migrate optimize rewrite implement
         analyze].each do |kw|
        expect(described_class.heuristic("please #{kw} this code")).to eq(described_class::AUTO_MODEL_PRO)
      end
    end

    it 'returns flash for short inputs' do
      expect(described_class.heuristic('hello')).to eq(described_class::AUTO_MODEL_FLASH)
    end

    it 'returns pro for long inputs' do
      long_input = 'a' * 501
      expect(described_class.heuristic(long_input)).to eq(described_class::AUTO_MODEL_PRO)
    end

    it 'returns flash for medium inputs without complex keywords' do
      medium_input = 'a' * 200
      expect(described_class.heuristic(medium_input)).to eq(described_class::AUTO_MODEL_FLASH)
    end

    it 'is case-insensitive for keywords' do
      expect(described_class.heuristic('REFACTOR the module')).to eq(described_class::AUTO_MODEL_PRO)
    end
  end

  describe '.normalize_model' do
    it 'normalizes pro variants' do
      expect(described_class.normalize_model('deepseek-v4-pro')).to eq('deepseek-v4-pro')
      expect(described_class.normalize_model('v4-pro')).to eq('deepseek-v4-pro')
      expect(described_class.normalize_model('pro')).to eq('deepseek-v4-pro')
    end

    it 'normalizes flash variants' do
      expect(described_class.normalize_model('deepseek-v4-flash')).to eq('deepseek-v4-flash')
      expect(described_class.normalize_model('v4-flash')).to eq('deepseek-v4-flash')
      expect(described_class.normalize_model('flash')).to eq('deepseek-v4-flash')
    end

    it 'returns nil for unknown models' do
      expect(described_class.normalize_model('gpt-4')).to be_nil
    end

    it 'returns nil for non-string input' do
      expect(described_class.normalize_model(nil)).to be_nil
      expect(described_class.normalize_model(123)).to be_nil
    end
  end

  describe '.normalize_effort' do
    it 'normalizes off variants' do
      %w[off disabled none false].each do |v|
        expect(described_class.normalize_effort(v)).to eq('off')
      end
    end

    it 'normalizes high variants' do
      %w[low minimal medium mid high].each do |v|
        expect(described_class.normalize_effort(v)).to eq('high')
      end
    end

    it 'normalizes max variants' do
      %w[max maximum xhigh].each do |v|
        expect(described_class.normalize_effort(v)).to eq('max')
      end
    end

    it 'returns nil for unknown efforts' do
      expect(described_class.normalize_effort('unknown')).to be_nil
    end

    it 'returns nil for non-string input' do
      expect(described_class.normalize_effort(nil)).to be_nil
    end
  end

  describe '.reasoning_heuristic' do
    it 'returns max for debug/error inputs' do
      expect(described_class.reasoning_heuristic('debug this issue')).to eq('max')
      expect(described_class.reasoning_heuristic('there is an error')).to eq('max')
    end

    it 'returns high for other inputs' do
      expect(described_class.reasoning_heuristic('write a function')).to eq('high')
    end
  end

  describe '.parse_recommendation' do
    it 'parses valid JSON recommendation' do
      raw = '{"model":"deepseek-v4-pro","thinking":"high"}'
      result = described_class.parse_recommendation(raw)
      expect(result[:model]).to eq('deepseek-v4-pro')
      expect(result[:reasoning_effort]).to eq('high')
    end

    it 'returns nil for invalid JSON' do
      expect(described_class.parse_recommendation('not json')).to be_nil
    end

    it 'returns nil for unknown model' do
      raw = '{"model":"gpt-4","thinking":"high"}'
      expect(described_class.parse_recommendation(raw)).to be_nil
    end

    it 'handles text with embedded JSON' do
      raw = 'Here is the result: {"model":"flash","thinking":"off"}'
      result = described_class.parse_recommendation(raw)
      expect(result[:model]).to eq('deepseek-v4-flash')
      expect(result[:reasoning_effort]).to eq('off')
    end

    it 'handles recommendation with reasoning_effort key' do
      raw = '{"model":"pro","reasoning_effort":"max"}'
      result = described_class.parse_recommendation(raw)
      expect(result[:model]).to eq('deepseek-v4-pro')
      expect(result[:reasoning_effort]).to eq('max')
    end

    it 'returns nil for empty string' do
      expect(described_class.parse_recommendation('')).to be_nil
    end
  end

  describe '.recent_context' do
    it 'returns No prior context when empty' do
      expect(described_class.recent_context([], 't1')).to eq('No prior context.')
    end

    it 'excludes current turn items' do
      items = [
        { turn_id: 't1', kind: 'user_message', text: 'hello' },
        { turn_id: 't2', kind: 'assistant_text', text: 'hi' }
      ]
      result = described_class.recent_context(items, 't1')
      expect(result).not_to include('hello')
      expect(result).to include('hi')
    end

    it 'limits to 6 items' do
      items = (1..10).map { |i| { turn_id: "t#{i}", kind: 'user_message', text: "msg#{i}" } }
      result = described_class.recent_context(items, 't99')
      lines = result.split("\n")
      expect(lines.length).to be <= 6
    end
  end

  describe '.fallback_auto_route' do
    it 'returns a route with heuristic model' do
      result = described_class.fallback_auto_route('hello', '')
      expect(result[:model]).to be_a(String)
      expect(result[:reasoning_effort]).to be_a(String)
      expect(result[:source]).to eq('heuristic')
    end
  end

  describe '.truncate_for_auto_router' do
    it 'returns short text unchanged' do
      expect(described_class.truncate_for_auto_router('hello', 10)).to eq('hello')
    end

    it 'truncates long text with ellipsis' do
      result = described_class.truncate_for_auto_router('a' * 20, 10)
      expect(result.length).to eq(13)
      expect(result).to end_with('...')
    end
  end

  describe '.extract_first_json_object' do
    it 'extracts JSON from surrounding text' do
      result = described_class.extract_first_json_object('prefix {"a":1} suffix')
      expect(result).to eq('{"a":1}')
    end

    it 'returns nil when no braces found' do
      expect(described_class.extract_first_json_object('no json here')).to be_nil
    end

    it 'extracts nested JSON' do
      result = described_class.extract_first_json_object('{"outer":{"inner":1}}')
      expect(result).to eq('{"outer":{"inner":1}}')
    end
  end

  describe '.resolve' do
    let(:abort_signal) { double('signal', aborted?: false) }

    it 'returns a route with heuristic source' do
      result = described_class.resolve(
        latest_request: 'hello',
        selected_model_mode: 'auto',
        abort_signal: abort_signal
      )
      expect(result[:source]).to eq('heuristic')
      expect(result[:model]).to be_a(String)
    end

    it 'returns fallback when signal is aborted' do
      aborted_signal = double('signal', aborted?: true)
      result = described_class.resolve(
        latest_request: 'hello',
        selected_model_mode: 'auto',
        abort_signal: aborted_signal
      )
      expect(result[:model]).to be_a(String)
    end
  end

  describe '.router_role_for_item' do
    it 'returns correct roles' do
      expect(described_class.router_role_for_item({ kind: 'user_message' })).to eq('user')
      expect(described_class.router_role_for_item({ kind: 'tool_result' })).to eq('tool')
      expect(described_class.router_role_for_item({ kind: 'compaction' })).to eq('system')
      expect(described_class.router_role_for_item({ kind: 'assistant_text' })).to eq('assistant')
    end
  end

  describe '.router_text_for_item' do
    it 'returns text for user_message' do
      expect(described_class.router_text_for_item({ kind: 'user_message', text: 'hi' })).to eq('hi')
    end

    it 'returns tool call description' do
      result = described_class.router_text_for_item({ kind: 'tool_call', tool_name: 'read' })
      expect(result).to include('read')
    end

    it 'returns empty string for unknown kind' do
      expect(described_class.router_text_for_item({ kind: 'unknown' })).to eq('')
    end
  end
end
