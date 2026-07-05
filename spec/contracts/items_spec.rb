# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'TurnItemRole constants' do
    it 'defines USER, ASSISTANT, SYSTEM, TOOL' do
      expect(described_class::TurnItemRole::USER).to eq('user')
      expect(described_class::TurnItemRole::ASSISTANT).to eq('assistant')
      expect(described_class::TurnItemRole::SYSTEM).to eq('system')
      expect(described_class::TurnItemRole::TOOL).to eq('tool')
    end
  end

  describe 'TurnItemStatus constants' do
    it 'defines all statuses' do
      expect(described_class::TurnItemStatus::PENDING).to eq('pending')
      expect(described_class::TurnItemStatus::RUNNING).to eq('running')
      expect(described_class::TurnItemStatus::COMPLETED).to eq('completed')
      expect(described_class::TurnItemStatus::FAILED).to eq('failed')
      expect(described_class::TurnItemStatus::ABORTED).to eq('aborted')
    end
  end

  describe 'ToolKind constants' do
    it 'defines TOOL_CALL, COMMAND_EXECUTION, FILE_CHANGE' do
      expect(described_class::ToolKind::TOOL_CALL).to eq('tool_call')
      expect(described_class::ToolKind::COMMAND_EXECUTION).to eq('command_execution')
      expect(described_class::ToolKind::FILE_CHANGE).to eq('file_change')
    end
  end

  describe 'TurnItem struct types' do
    it 'UserTurnItem has expected fields' do
      item = described_class::UserTurnItem.new(
        id: 'u1', turn_id: 'tr1', thread_id: 't1', role: 'user',
        status: 'completed', kind: 'user_message', text: 'hello'
      )
      expect(item.text).to eq('hello')
    end

    it 'AssistantTextTurnItem has expected fields' do
      item = described_class::AssistantTextTurnItem.new(
        id: 'a1', turn_id: 'tr1', thread_id: 't1', role: 'assistant',
        status: 'running', kind: 'assistant_text', text: 'response'
      )
      expect(item.text).to eq('response')
    end

    it 'ToolCallTurnItem has tool_name and call_id' do
      item = described_class::ToolCallTurnItem.new(
        id: 'tc1', turn_id: 'tr1', thread_id: 't1', role: 'tool',
        status: 'pending', kind: 'tool_call', tool_name: 'bash',
        call_id: 'c1', arguments: { cmd: 'ls' }
      )
      expect(item.call_id).to eq('c1')
    end

    it 'ToolResultTurnItem has output and is_error' do
      item = described_class::ToolResultTurnItem.new(
        id: 'tr1', turn_id: 'tr1', thread_id: 't1', role: 'tool',
        status: 'completed', kind: 'tool_result', tool_name: 'bash',
        call_id: 'c1', output: 'file1', is_error: false
      )
      expect(item.output).to eq('file1')
      expect(item.is_error).to be(false)
    end

    it 'CompactionTurnItem has summary and source_digest' do
      item = described_class::CompactionTurnItem.new(
        id: 'cp1', turn_id: 'tr1', thread_id: 't1', role: 'system',
        status: 'completed', kind: 'compaction', summary: 'compressed',
        replaced_tokens: 500
      )
      expect(item.summary).to eq('compressed')
    end

    it 'ErrorTurnItem has message and code' do
      item = described_class::ErrorTurnItem.new(
        id: 'e1', turn_id: 'tr1', thread_id: 't1', role: 'system',
        status: 'failed', kind: 'error', message: 'fail', code: 'E1'
      )
      expect(item.message).to eq('fail')
    end
  end

  describe 'TurnItem union type' do
    it 'contains all item types' do
      expect(described_class::TurnItem).to be_frozen
      expect(described_class::TurnItem.size).to eq(10)
      expect(described_class::TurnItem).to include(described_class::UserTurnItem)
      expect(described_class::TurnItem).to include(described_class::ToolCallTurnItem)
      expect(described_class::TurnItem).to include(described_class::ErrorTurnItem)
    end
  end
end
