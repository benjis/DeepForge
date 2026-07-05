# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'TurnStatus constants' do
    it 'defines all statuses' do
      expect(described_class::TurnStatus::QUEUED).to eq('queued')
      expect(described_class::TurnStatus::RUNNING).to eq('running')
      expect(described_class::TurnStatus::COMPLETED).to eq('completed')
      expect(described_class::TurnStatus::FAILED).to eq('failed')
      expect(described_class::TurnStatus::ABORTED).to eq('aborted')
    end
  end

  describe 'TurnReasoningEffort constants' do
    it 'defines all effort levels' do
      expect(described_class::TurnReasoningEffort::AUTO).to eq('auto')
      expect(described_class::TurnReasoningEffort::OFF).to eq('off')
      expect(described_class::TurnReasoningEffort::LOW).to eq('low')
      expect(described_class::TurnReasoningEffort::MEDIUM).to eq('medium')
      expect(described_class::TurnReasoningEffort::HIGH).to eq('high')
      expect(described_class::TurnReasoningEffort::MAX).to eq('max')
    end
  end

  describe 'GuiPlanOperation constants' do
    it 'defines DRAFT and REFINE' do
      expect(described_class::GuiPlanOperation::DRAFT).to eq('draft')
      expect(described_class::GuiPlanOperation::REFINE).to eq('refine')
    end
  end

  describe 'Turn struct' do
    it 'creates with keyword init' do
      turn = described_class::Turn.new(
        id: 'tr1', thread_id: 't1', status: 'queued', prompt: 'hello'
      )
      expect(turn.id).to eq('tr1')
      expect(turn.status).to eq('queued')
    end
  end

  describe 'StartTurnRequest' do
    it 'supports keyword init' do
      req = described_class::StartTurnRequest.new(prompt: 'hello', model: 'm')
      expect(req.prompt).to eq('hello')
    end
  end

  describe 'StartTurnResponse' do
    it 'supports keyword init' do
      resp = described_class::StartTurnResponse.new(thread_id: 't1', turn_id: 'tr1')
      expect(resp.thread_id).to eq('t1')
    end
  end

  describe 'SteerTurnRequest' do
    it 'supports keyword init' do
      req = described_class::SteerTurnRequest.new(text: 'new direction')
      expect(req.text).to eq('new direction')
    end
  end

  describe 'InterruptTurnRequest' do
    it 'supports keyword init' do
      req = described_class::InterruptTurnRequest.new(discard: true)
      expect(req.discard).to be(true)
    end
  end

  describe 'CompactRequest' do
    it 'supports keyword init' do
      req = described_class::CompactRequest.new(reason: 'too long', budget_tokens: 1000)
      expect(req.reason).to eq('too long')
    end
  end

  describe 'CompactResponse' do
    it 'supports keyword init' do
      resp = described_class::CompactResponse.new(thread_id: 't1', replaced_tokens: 500)
      expect(resp.replaced_tokens).to eq(500)
    end
  end
end
