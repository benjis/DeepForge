# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/read_tracker'

RSpec.describe DeepForge::Adapters::Tool::ReadTracker do
  let(:enabled_options) { described_class.normalize_read_tracker_options(true) }
  let(:disabled_options) { described_class.normalize_read_tracker_options(false) }

  describe '.normalize_read_tracker_options' do
    it 'returns enabled options for true' do
      opts = described_class.normalize_read_tracker_options(true)
      expect(opts.enabled).to be true
      expect(opts.require_old_text_in_read).to be true
    end

    it 'returns disabled options for false' do
      opts = described_class.normalize_read_tracker_options(false)
      expect(opts.enabled).to be false
    end

    it 'returns disabled options for nil' do
      opts = described_class.normalize_read_tracker_options(nil)
      expect(opts.enabled).to be false
    end

    it 'normalizes a ReadTrackerOptions input' do
      input = DeepForge::Adapters::Tool::ReadTrackerOptions.new(enabled: true, require_old_text_in_read: false)
      opts = described_class.normalize_read_tracker_options(input)
      expect(opts.enabled).to be true
      expect(opts.require_old_text_in_read).to be false
    end

    it 'returns disabled for unknown types' do
      opts = described_class.normalize_read_tracker_options('invalid')
      expect(opts.enabled).to be false
    end
  end

  describe '#observe_tool_result' do
    let(:tracker) { described_class.new(enabled_options) }
    let(:context) do
      Struct.new(:thread_id, :turn_id, :workspace).new('t1', 'r1', '/workspace')
    end
    let(:read_call) do
      Struct.new(:tool_name, :arguments, :call_id).new('read', { path: 'file.txt' }, 'c1')
    end

    it 'records a successful read tool result' do
      output = { path: '/workspace/file.txt', content: 'hello', truncated: false, relative_path: 'file.txt' }
      tracker.observe_tool_result(context: context, call: read_call, output: output)
      result = tracker.validate_before_tool(context: context, call: read_call)
      expect(result[:ok]).to be true
    end

    it 'ignores error results' do
      output = { path: '/workspace/file.txt', error: 'not found' }
      tracker.observe_tool_result(context: context, call: read_call, output: output, is_error: true)
      edit_call = Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: 'file.txt' }, 'c1')
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be false
    end

    it 'ignores non-read tool calls' do
      bash_call = Struct.new(:tool_name, :arguments, :call_id).new('bash', {}, 'c2')
      output = { path: '/workspace/file.txt' }
      tracker.observe_tool_result(context: context, call: bash_call, output: output)
      edit_call = Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: 'file.txt' }, 'c1')
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be false
    end

    it 'ignores results with empty path' do
      output = { path: '', content: 'hello' }
      tracker.observe_tool_result(context: context, call: read_call, output: output)
      edit_call = Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: 'file.txt' }, 'c1')
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be false
    end
  end

  describe '#validate_before_tool' do
    let(:tracker) { described_class.new(enabled_options) }
    let(:context) do
      Struct.new(:thread_id, :turn_id, :workspace).new('t1', 'r1', '/workspace')
    end
    let(:edit_call) do
      Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: 'file.txt', old_text: 'hello' }, 'c1')
    end

    it 'allows non-edit tools' do
      bash_call = Struct.new(:tool_name, :arguments, :call_id).new('bash', { command: 'echo hi' }, 'c2')
      result = tracker.validate_before_tool(context: context, call: bash_call)
      expect(result[:ok]).to be true
    end

    it 'blocks edit when file has not been read' do
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be false
      expect(result[:message]).to include('read-before-edit guard')
    end

    it 'allows edit when file was read in the same turn' do
      output = { path: '/workspace/file.txt', content: 'hello world', truncated: false }
      read_call = Struct.new(:tool_name, :arguments, :call_id).new('read', { path: 'file.txt' }, 'c0')
      tracker.observe_tool_result(context: context, call: read_call, output: output)
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be true
    end

    it 'blocks edit when file was read in a previous turn' do
      output = { path: '/workspace/file.txt', content: 'hello world', truncated: false }
      read_call = Struct.new(:tool_name, :arguments, :call_id).new('read', { path: 'file.txt' }, 'c0')
      tracker.observe_tool_result(context: context, call: read_call, output: output)

      future_context = Struct.new(:thread_id, :turn_id, :workspace).new('t1', 'r2', '/workspace')
      result = tracker.validate_before_tool(context: future_context, call: edit_call)
      expect(result[:ok]).to be false
      expect(result[:message]).to include('earlier turn')
    end

    it 'allows edit with empty path' do
      empty_call = Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: '' }, 'c1')
      result = tracker.validate_before_tool(context: context, call: empty_call)
      expect(result[:ok]).to be true
    end
  end

  describe '#clear' do
    let(:tracker) { described_class.new(enabled_options) }
    let(:context) do
      Struct.new(:thread_id, :turn_id, :workspace).new('t1', 'r1', '/workspace')
    end

    it 'clears records for a specific thread' do
      output = { path: '/workspace/file.txt', content: 'hello', truncated: false }
      read_call = Struct.new(:tool_name, :arguments, :call_id).new('read', { path: 'file.txt' }, 'c0')
      tracker.observe_tool_result(context: context, call: read_call, output: output)
      tracker.clear('t1')
      edit_call = Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: 'file.txt' }, 'c1')
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be false
    end

    it 'clears all records when no thread_id given' do
      output = { path: '/workspace/file.txt', content: 'hello', truncated: false }
      read_call = Struct.new(:tool_name, :arguments, :call_id).new('read', { path: 'file.txt' }, 'c0')
      tracker.observe_tool_result(context: context, call: read_call, output: output)
      tracker.clear
      edit_call = Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: 'file.txt' }, 'c1')
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be false
    end
  end

  describe 'with disabled options' do
    let(:tracker) { described_class.new(disabled_options) }
    let(:context) do
      Struct.new(:thread_id, :turn_id, :workspace).new('t1', 'r1', '/workspace')
    end

    it 'always allows edits when disabled' do
      edit_call = Struct.new(:tool_name, :arguments, :call_id).new('edit', { path: 'file.txt' }, 'c1')
      result = tracker.validate_before_tool(context: context, call: edit_call)
      expect(result[:ok]).to be true
    end
  end
end
