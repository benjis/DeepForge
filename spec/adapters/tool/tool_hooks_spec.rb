# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/tool_hooks'

RSpec.describe DeepForge::Adapters::Tool::ToolHooks do
  let(:tool_call) do
    Struct.new(:tool_name, :arguments, :call_id, :provider_id, :tool_kind).new(
      'bash', { command: 'echo hi' }, 'call_1', nil, nil
    )
  end

  let(:pre_context) do
    { thread_id: 't1', turn_id: 'r1', workspace: '/tmp', approval_policy: 'auto', thread_mode: 'code' }
  end

  describe '.run_tool_hooks' do
    it 'returns empty array when no hooks match' do
      hook = DeepForge::Adapters::Tool::ResolvedToolHook.new(
        phase: 'PostToolUse', tool_names: nil, timeout_ms: 1000, run: ->(_i) {}
      )
      invocation = DeepForge::Adapters::Tool::ToolHookInvocation.new(
        phase: 'PreToolUse', call: tool_call, context: pre_context
      )
      results = described_class.run_tool_hooks(hooks: [hook], invocation: invocation)
      expect(results).to eq([])
    end

    it 'runs matching function hooks' do
      hook = DeepForge::Adapters::Tool::ResolvedToolHook.new(
        phase: 'PreToolUse', tool_names: ['bash'], timeout_ms: 1000,
        run: ->(_inv) { DeepForge::Adapters::Tool::ToolHookResult.new(decision: 'allow') }
      )
      invocation = DeepForge::Adapters::Tool::ToolHookInvocation.new(
        phase: 'PreToolUse', call: tool_call, context: pre_context
      )
      results = described_class.run_tool_hooks(hooks: [hook], invocation: invocation)
      expect(results.length).to eq(1)
      expect(results.first.decision).to eq('allow')
    end

    it 'skips hooks with non-matching tool names' do
      hook = DeepForge::Adapters::Tool::ResolvedToolHook.new(
        phase: 'PreToolUse', tool_names: ['read'], timeout_ms: 1000,
        run: ->(_inv) { DeepForge::Adapters::Tool::ToolHookResult.new(decision: 'allow') }
      )
      invocation = DeepForge::Adapters::Tool::ToolHookInvocation.new(
        phase: 'PreToolUse', call: tool_call, context: pre_context
      )
      results = described_class.run_tool_hooks(hooks: [hook], invocation: invocation)
      expect(results).to eq([])
    end

    it 'runs hooks with nil tool_names (match all)' do
      hook = DeepForge::Adapters::Tool::ResolvedToolHook.new(
        phase: 'PreToolUse', tool_names: nil, timeout_ms: 1000,
        run: ->(_inv) { DeepForge::Adapters::Tool::ToolHookResult.new(decision: 'allow') }
      )
      invocation = DeepForge::Adapters::Tool::ToolHookInvocation.new(
        phase: 'PreToolUse', call: tool_call, context: pre_context
      )
      results = described_class.run_tool_hooks(hooks: [hook], invocation: invocation)
      expect(results.length).to eq(1)
    end

    it 'skips nil results from hooks' do
      hook = DeepForge::Adapters::Tool::ResolvedToolHook.new(
        phase: 'PreToolUse', tool_names: ['bash'], timeout_ms: 1000, run: ->(_inv) {}
      )
      invocation = DeepForge::Adapters::Tool::ToolHookInvocation.new(
        phase: 'PreToolUse', call: tool_call, context: pre_context
      )
      results = described_class.run_tool_hooks(hooks: [hook], invocation: invocation)
      expect(results).to eq([])
    end
  end

  describe '.apply_pre_tool_hook_results' do
    it 'returns call unchanged when no results' do
      result = described_class.apply_pre_tool_hook_results(tool_call, [])
      expect(result[:call]).to equal(tool_call)
      expect(result[:denied]).to be_nil
    end

    it 'denies call when a hook returns deny decision' do
      hook_result = DeepForge::Adapters::Tool::ToolHookResult.new(decision: 'deny', message: 'blocked')
      result = described_class.apply_pre_tool_hook_results(tool_call, [hook_result])
      expect(result[:denied]).to eq('blocked')
    end

    it 'modifies arguments when hook returns new arguments' do
      hook_result = DeepForge::Adapters::Tool::ToolHookResult.new(arguments: { command: 'echo modified' })
      result = described_class.apply_pre_tool_hook_results(tool_call, [hook_result])
      expect(result[:call].arguments[:command]).to eq('echo modified')
      expect(result[:denied]).to be_nil
    end
  end

  describe '.apply_post_tool_hook_results' do
    it 'returns result unchanged when no hook results' do
      original = { output: { data: 'hi' } }
      result = described_class.apply_post_tool_hook_results(original, [])
      expect(result).to eq(original)
    end

    it 'replaces output when hook provides output' do
      hook_result = DeepForge::Adapters::Tool::ToolHookResult.new(output: { replaced: true })
      result = described_class.apply_post_tool_hook_results({ output: { old: true } }, [hook_result])
      expect(result[:output]).to eq({ replaced: true })
    end

    it 'sets is_error when hook provides is_error' do
      hook_result = DeepForge::Adapters::Tool::ToolHookResult.new(is_error: true)
      result = described_class.apply_post_tool_hook_results({ output: { data: 'hi' } }, [hook_result])
      expect(result[:is_error]).to be true
    end
  end
end
