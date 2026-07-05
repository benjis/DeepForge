# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  let(:base_input) { { id: 'i1', turn_id: 'tr1', thread_id: 't1' } }

  describe '.make_user_item' do
    it 'creates a user message item with completed status' do
      item = described_class.make_user_item(base_input.merge(text: 'hello'))
      expect(item.kind).to eq('user_message')
      expect(item.role).to eq('user')
      expect(item.status).to eq('completed')
      expect(item.text).to eq('hello')
      expect(item.id).to eq('i1')
    end

    it 'strips display_text when it equals text' do
      item = described_class.make_user_item(base_input.merge(text: 'hello', display_text: 'hello'))
      expect(item.display_text).to be_nil
    end

    it 'keeps display_text when different from text' do
      item = described_class.make_user_item(base_input.merge(text: 'hello', display_text: 'Hello'))
      expect(item.display_text).to eq('Hello')
    end

    it 'strips whitespace from display_text' do
      item = described_class.make_user_item(base_input.merge(text: 'hello', display_text: '  Hello  '))
      expect(item.display_text).to eq('Hello')
    end

    it 'filters out blank attachment IDs' do
      item = described_class.make_user_item(base_input.merge(text: 'hi', attachment_ids: ['a1', '  ', 'a2']))
      expect(item.attachment_ids).to eq(%w[a1 a2])
    end

    it 'sets attachment_ids to nil when all are blank' do
      item = described_class.make_user_item(base_input.merge(text: 'hi', attachment_ids: ['  ', '']))
      expect(item.attachment_ids).to be_nil
    end

    it 'sets attachment_ids to nil when nil' do
      item = described_class.make_user_item(base_input.merge(text: 'hi'))
      expect(item.attachment_ids).to be_nil
    end
  end

  describe '.make_assistant_text_item' do
    it 'creates an assistant text item with running status' do
      item = described_class.make_assistant_text_item(base_input.merge(text: 'response'))
      expect(item.kind).to eq('assistant_text')
      expect(item.role).to eq('assistant')
      expect(item.status).to eq('running')
      expect(item.text).to eq('response')
    end

    it 'uses provided status' do
      item = described_class.make_assistant_text_item(base_input.merge(text: 'x', status: 'completed'))
      expect(item.status).to eq('completed')
    end
  end

  describe '.make_assistant_reasoning_item' do
    it 'creates a reasoning item' do
      item = described_class.make_assistant_reasoning_item(base_input.merge(text: 'thinking'))
      expect(item.kind).to eq('assistant_reasoning')
      expect(item.role).to eq('assistant')
      expect(item.status).to eq('running')
    end
  end

  describe '.make_tool_call_item' do
    it 'creates a tool call item with pending status' do
      item = described_class.make_tool_call_item(
        base_input.merge(tool_name: 'bash', call_id: 'c1', arguments: { cmd: 'ls' })
      )
      expect(item.kind).to eq('tool_call')
      expect(item.role).to eq('tool')
      expect(item.status).to eq('pending')
      expect(item.tool_name).to eq('bash')
      expect(item.call_id).to eq('c1')
    end

    it 'uses provided tool_kind' do
      item = described_class.make_tool_call_item(
        base_input.merge(tool_name: 'bash', call_id: 'c1', arguments: {}, tool_kind: 'file_change')
      )
      expect(item.tool_kind).to eq('file_change')
    end
  end

  describe '.make_tool_result_item' do
    it 'creates a tool result item with completed status' do
      item = described_class.make_tool_result_item(
        base_input.merge(tool_name: 'bash', call_id: 'c1', output: 'result')
      )
      expect(item.kind).to eq('tool_result')
      expect(item.status).to eq('completed')
      expect(item.finished_at).to match(/\d{4}/)
    end

    it 'sets finished_at to nil for running status' do
      item = described_class.make_tool_result_item(
        base_input.merge(tool_name: 'bash', call_id: 'c1', output: '', status: 'running')
      )
      expect(item.finished_at).to be_nil
    end

    it 'defaults is_error to false' do
      item = described_class.make_tool_result_item(
        base_input.merge(tool_name: 'bash', call_id: 'c1', output: '')
      )
      expect(item.is_error).to be(false)
    end
  end

  describe '.make_approval_item' do
    it 'creates an approval item with pending status' do
      item = described_class.make_approval_item(
        base_input.merge(approval_id: 'a1', tool_name: 'bash', summary: 'run')
      )
      expect(item.kind).to eq('approval')
      expect(item.status).to eq('pending')
      expect(item.approval_id).to eq('a1')
    end
  end

  describe '.make_user_input_item' do
    it 'creates a user input item' do
      item = described_class.make_user_input_item(
        base_input.merge(input_id: 'u1', prompt: 'pick one', questions: [])
      )
      expect(item.kind).to eq('user_input')
      expect(item.status).to eq('pending')
      expect(item.input_id).to eq('u1')
    end

    it 'defaults questions to empty array' do
      item = described_class.make_user_input_item(
        base_input.merge(input_id: 'u1', prompt: 'pick')
      )
      expect(item.questions).to eq([])
    end
  end

  describe '.make_compaction_item' do
    it 'creates a compaction item' do
      item = described_class.make_compaction_item(
        base_input.merge(summary: 'compressed', replaced_tokens: 100, pinned_constraints: ['rule'],
                         source_digest: 'abc', digest_marker: 'marker', source_item_ids: ['i2'])
      )
      expect(item.kind).to eq('compaction')
      expect(item.role).to eq('system')
      expect(item.status).to eq('completed')
      expect(item.replaced_tokens).to eq(100)
    end

    it 'dups source_item_ids to avoid shared mutation' do
      ids = ['i2']
      item = described_class.make_compaction_item(base_input.merge(source_item_ids: ids, summary: 's'))
      ids << 'i3'
      expect(item.source_item_ids).to eq(['i2'])
    end
  end

  describe '.make_review_item' do
    it 'creates a review item with running status by default' do
      item = described_class.make_review_item(
        base_input.merge(target: 'branch', title: 'Review PR')
      )
      expect(item.kind).to eq('review')
      expect(item.status).to eq('running')
    end

    it 'sets finished_at when status is completed' do
      item = described_class.make_review_item(
        base_input.merge(target: 'branch', title: 'R', status: 'completed')
      )
      expect(item.finished_at).to match(/\d{4}/)
    end
  end

  describe '.make_error_item' do
    it 'creates an error item with failed status' do
      item = described_class.make_error_item(
        base_input.merge(message: 'boom', code: 'ERR')
      )
      expect(item.kind).to eq('error')
      expect(item.status).to eq('failed')
      expect(item.role).to eq('system')
      expect(item.message).to eq('boom')
      expect(item.code).to eq('ERR')
    end
  end
end
