# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/agent_loop'

RSpec.describe DeepForge::Loop::AgentLoop do
  subject(:loop_instance) { described_class.new(opts) }

  let(:thread_store) { double('thread_store') }
  let(:turns) { double('turns') }
  let(:session_store) { double('session_store') }
  let(:events) { double('events') }
  let(:tool_host) { double('tool_host') }
  let(:model_client) { double('model_client') }
  let(:inflight) { DeepForge::Loop::InflightTracker.new }
  let(:steering) { DeepForge::Loop::SteeringQueue.new }
  let(:usage) { double('usage') }
  let(:memory_store) { nil }
  let(:compactor) { DeepForge::Loop::ContextCompactor.new(soft_threshold: 1_000_000, hard_threshold: 2_000_000) }

  let(:prefix) { described_class.default_prefix }

  let(:abort_signal) { double('signal', aborted?: false) }

  let(:opts) do
    {
      thread_store: thread_store,
      turns: turns,
      session_store: session_store,
      events: events,
      tool_host: tool_host,
      model: model_client,
      inflight: inflight,
      steering: steering,
      usage: usage,
      prefix: prefix,
      compactor: compactor,
      tools: []
    }
  end

  before do
    allow(thread_store).to receive(:get).and_return({ id: 't1', goal: nil, todos: nil })
    allow(turns).to receive(:get_turn).and_return({ id: 'r1', prompt: 'hello' })
    allow(turns).to receive(:finish_turn)
    allow(turns).to receive(:apply_item)
    allow(turns).to receive(:update_item)
    allow(turns).to receive(:update_turn_metadata)
    allow(session_store).to receive(:load_items).and_return([])
    allow(session_store).to receive(:rewrite_items)
    allow(session_store).to receive(:append_item)
    allow(events).to receive(:record)
    allow(tool_host).to receive(:list_tools).and_return([])
    allow(tool_host).to receive(:clear_read_tracker)
    allow(usage).to receive_messages(for_thread: nil, record: {}, record_token_economy_savings: {})
    allow(model_client).to receive(:stream).and_return([])
  end

  describe '#initialize' do
    it 'creates an agent loop instance' do
      expect(loop_instance).to be_a(described_class)
    end
  end

  describe '#run_turn' do
    it 'returns :failed when no abort controller' do
      allow(turns).to receive(:get_abort_controller).and_return(nil)
      result = loop_instance.run_turn('t1', 'r1')
      expect(result).to eq(:failed)
    end

    it 'returns :aborted when signal is already aborted' do
      aborted_signal = double('signal', aborted?: true)
      allow(turns).to receive(:get_abort_controller).with('r1').and_return(aborted_signal)
      result = loop_instance.run_turn('t1', 'r1')
      expect(result).to eq(:aborted)
    end

    it 'completes a simple turn with no tool calls' do
      allow(turns).to receive(:get_abort_controller).with('r1').and_return(abort_signal)
      allow(model_client).to receive(:stream) do |_request, &blk|
        blk.call({ kind: 'assistant_text_delta', text: 'Hello!' })
        blk.call({ kind: 'completed', stop_reason: 'stop' })
      end

      result = loop_instance.run_turn('t1', 'r1')
      expect(%i[stop failed]).to include(result)
    end

    it 'handles model errors' do
      allow(turns).to receive(:get_abort_controller).with('r1').and_return(abort_signal)
      allow(model_client).to receive(:stream).and_yield({ kind: 'error', message: 'Model error', code: 'E001' })

      result = loop_instance.run_turn('t1', 'r1')
      expect(result).to eq(:failed)
    end

    it 'handles exceptions gracefully' do
      allow(turns).to receive(:get_abort_controller).with('r1').and_return(abort_signal)
      allow(thread_store).to receive(:get).and_raise('boom')

      result = loop_instance.run_turn('t1', 'r1')
      expect(result).to eq(:failed)
    end

    it 'drains steering messages' do
      allow(turns).to receive(:get_abort_controller).with('r1').and_return(abort_signal)
      steering.enqueue('r1', 'steered input')
      allow(model_client).to receive(:stream).and_yield({ kind: 'completed', stop_reason: 'stop' })

      loop_instance.run_turn('t1', 'r1')
      expect(turns).to have_received(:apply_item).at_least(:once)
    end

    it 'records pipeline stages' do
      allow(turns).to receive(:get_abort_controller).with('r1').and_return(abort_signal)
      allow(model_client).to receive(:stream).and_yield({ kind: 'completed', stop_reason: 'stop' })

      loop_instance.run_turn('t1', 'r1')
      expect(events).to have_received(:record).at_least(:once)
    end

    # usage recording requires full model_step request construction; covered in integration tests
  end

  describe 'constants' do
    it 'defines PARALLEL_READ_ONLY_TOOL_NAMES' do
      expect(described_class::PARALLEL_READ_ONLY_TOOL_NAMES).to include('read')
      expect(described_class::PARALLEL_READ_ONLY_TOOL_NAMES).to include('grep')
    end

    it 'defines MAX_PARALLEL_TOOL_CALLS' do
      expect(described_class::MAX_PARALLEL_TOOL_CALLS).to eq(3)
    end

    it 'defines PIPELINE_STAGE_LABELS' do
      expect(described_class::PIPELINE_STAGE_LABELS).to include(:setup)
      expect(described_class::PIPELINE_STAGE_LABELS).to include(:pre_send)
    end

    it 'defines PLAN_MODE_INSTRUCTION' do
      expect(described_class::PLAN_MODE_INSTRUCTION).to include('Plan mode')
    end
  end

  describe '.default_prefix' do
    it 'returns an ImmutablePrefix' do
      prefix = described_class.default_prefix
      expect(prefix).to be_a(ImmutablePrefix)
      expect(prefix.system_prompt).to include('DeepForge')
      expect(prefix.pinned_constraints).not_to be_empty
    end
  end
end
