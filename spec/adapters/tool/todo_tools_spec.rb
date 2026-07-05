# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/todo_tools'

RSpec.describe DeepForge::Adapters::Tool::TodoTools do
  let(:thread_service) { double('thread_service') }

  describe '.build' do
    it 'returns 2 todo tools' do
      tools = described_class.build(thread_service)
      expect(tools.length).to eq(2)
      names = tools.map { |t| t[:name] }
      expect(names).to contain_exactly('todo_list', 'todo_write')
    end
  end

  describe 'todo_list tool' do
    let(:tool) { described_class.create_todo_list_tool(thread_service) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('todo_list')
      expect(tool[:policy]).to eq('auto')
    end

    it 'returns todos from thread service' do
      allow(thread_service).to receive(:get_todos).with('t1').and_return([
                                                                           { content: 'task 1', status: 'pending' }
                                                                         ])
      result = tool[:execute].call({}, { thread_id: 't1' })
      expect(result[:output][:todos].length).to eq(1)
      expect(result[:output][:todos].first[:content]).to eq('task 1')
    end
  end

  describe 'todo_write tool' do
    let(:tool) { described_class.create_todo_write_tool(thread_service) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('todo_write')
      expect(tool[:input_schema][:required]).to include('todos')
    end

    it 'writes todos' do
      allow(thread_service).to receive(:set_todos).and_return([
                                                                { content: 'task 1', status: 'pending' }
                                                              ])
      result = tool[:execute].call(
        { todos: [{ content: 'task 1', status: 'pending' }] },
        { thread_id: 't1' }
      )
      expect(result[:output][:todos].length).to eq(1)
    end

    it 'returns error for non-array todos' do
      result = tool[:execute].call({ todos: 'not an array' }, { thread_id: 't1' })
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('todos must be an array')
    end
  end

  describe '.normalize_tool_todos' do
    it 'keeps first in_progress' do
      todos = [
        { content: 'a', status: 'in_progress' },
        { content: 'b', status: 'in_progress' }
      ]
      result = described_class.normalize_tool_todos(todos)
      expect(result[0][:status]).to eq('in_progress')
      expect(result[1][:status]).to eq('pending')
    end

    it 'leaves non-in_progress unchanged' do
      todos = [
        { content: 'a', status: 'pending' },
        { content: 'b', status: 'completed' }
      ]
      result = described_class.normalize_tool_todos(todos)
      expect(result[0][:status]).to eq('pending')
      expect(result[1][:status]).to eq('completed')
    end
  end

  describe '.todo_response' do
    it 'wraps todos in output hash' do
      todos = [{ content: 'task' }]
      result = described_class.todo_response(todos)
      expect(result[:todos]).to eq(todos)
    end
  end

  describe '.error_output' do
    it 'returns error hash' do
      result = described_class.error_output('test')
      expect(result[:output][:error]).to eq('test')
      expect(result[:is_error]).to be true
    end
  end
end
