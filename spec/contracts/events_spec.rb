# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts::RuntimeEventKind do
  it 'defines all event kind constants' do
    expect(described_class::THREAD_CREATED).to eq('thread_created')
    expect(described_class::TURN_STARTED).to eq('turn_started')
    expect(described_class::ITEM_CREATED).to eq('item_created')
    expect(described_class::ASSISTANT_TEXT_DELTA).to eq('assistant_text_delta')
    expect(described_class::TOOL_CALL_STARTED).to eq('tool_call_started')
    expect(described_class::APPROVAL_REQUESTED).to eq('approval_requested')
    expect(described_class::COMPACTION_COMPLETED).to eq('compaction_completed')
    expect(described_class::USAGE).to eq('usage')
    expect(described_class::ERROR).to eq('error')
    expect(described_class::HEARTBEAT).to eq('heartbeat')
  end
end

RSpec.describe DeepForge::Contracts::RuntimeEvent do
  it 'is a frozen array of event struct classes' do
    expect(described_class).to be_frozen
    expect(described_class).to include(DeepForge::Contracts::ItemEvent)
    expect(described_class).to include(DeepForge::Contracts::TurnLifecycleEvent)
    expect(described_class).to include(DeepForge::Contracts::ErrorEvent)
    expect(described_class).to include(DeepForge::Contracts::UsageEvent)
  end
end

RSpec.describe DeepForge::Contracts::ItemEvent do
  it 'supports keyword init' do
    event = described_class.new(
      seq: 1, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
      kind: 'item_created', item_id: 'i1'
    )
    expect(event.seq).to eq(1)
    expect(event.kind).to eq('item_created')
  end
end

RSpec.describe DeepForge::Contracts::TurnLifecycleEvent do
  it 'supports keyword init' do
    event = described_class.new(
      seq: 2, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
      turn_id: 'tr1', kind: 'turn_started'
    )
    expect(event.turn_id).to eq('tr1')
  end
end

RSpec.describe DeepForge::Contracts::ApprovalEvent do
  it 'supports keyword init' do
    event = described_class.new(
      seq: 3, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
      kind: 'approval_requested', approval_id: 'a1', status: 'pending'
    )
    expect(event.approval_id).to eq('a1')
  end
end

RSpec.describe DeepForge::Contracts::ErrorEvent do
  it 'supports keyword init' do
    event = described_class.new(
      seq: 4, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
      kind: 'error', message: 'boom', code: 'E001'
    )
    expect(event.message).to eq('boom')
  end
end

RSpec.describe DeepForge::Contracts::UsageEvent do
  it 'supports keyword init' do
    event = described_class.new(
      seq: 5, timestamp: '2025-01-01T00:00:00Z', thread_id: 't1',
      kind: 'usage', model: 'deepseek', usage: {}
    )
    expect(event.model).to eq('deepseek')
  end
end
