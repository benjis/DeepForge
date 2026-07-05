# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/contracts/threads'
require 'deepforge/shared/todos'

RSpec.describe DeepForge::Shared do
  describe 'TASK_LINE_RE' do
    it 'matches unchecked task lines' do
      match = described_class::TASK_LINE_RE.match('- [ ] Buy milk')
      expect(match).not_to be_nil
      expect(match[2]).to eq(' ')
      expect(match[4]).to eq('Buy milk')
    end

    it 'matches checked task lines' do
      match = described_class::TASK_LINE_RE.match('- [x] Buy milk')
      expect(match).not_to be_nil
      expect(match[2]).to eq('x')
    end

    it 'matches task lines with * marker' do
      match = described_class::TASK_LINE_RE.match('* [ ] Item')
      expect(match).not_to be_nil
    end

    it 'matches task lines with + marker' do
      match = described_class::TASK_LINE_RE.match('+ [ ] Item')
      expect(match).not_to be_nil
    end

    it 'does not match non-task lines' do
      expect(described_class::TASK_LINE_RE.match('Regular text')).to be_nil
    end
  end

  describe '.normalize_todo_content' do
    it 'collapses whitespace' do
      expect(described_class.normalize_todo_content('  hello   world  ')).to eq('hello world')
    end

    it 'handles tabs and newlines' do
      expect(described_class.normalize_todo_content("hello\tworld\n")).to eq('hello world')
    end
  end

  describe '.todo_content_hash' do
    it 'returns a consistent hash for the same input' do
      hash1 = described_class.todo_content_hash('buy milk')
      hash2 = described_class.todo_content_hash('buy milk')
      expect(hash1).to eq(hash2)
    end

    it 'returns different hashes for different input' do
      hash1 = described_class.todo_content_hash('buy milk')
      hash2 = described_class.todo_content_hash('buy eggs')
      expect(hash1).not_to eq(hash2)
    end

    it 'is case insensitive' do
      hash1 = described_class.todo_content_hash('Buy Milk')
      hash2 = described_class.todo_content_hash('buy milk')
      expect(hash1).to eq(hash2)
    end

    it 'returns a string in base 36' do
      hash = described_class.todo_content_hash('test')
      expect(hash).to match(/\A[a-z0-9]+\z/)
    end
  end

  describe '.make_plan_todo_id' do
    it 'generates a todo ID from plan data' do
      id = described_class.make_plan_todo_id(
        plan_id: 'plan_1',
        relative_path: '.dfsdd/plan/feature.md',
        ordinal: 0,
        content_hash: 'abc'
      )
      expect(id).to start_with('todo_plan_')
    end
  end

  describe '.extract_plan_todos' do
    it 'extracts tasks from markdown' do
      markdown = "# Plan\n\n- [ ] Step 1\n- [x] Step 2\n- [ ] Step 3"
      items = described_class.extract_plan_todos(
        markdown: markdown,
        plan_id: 'plan_1',
        relative_path: '.dfsdd/plan/feature.md',
        now: '2024-01-01T00:00:00Z'
      )

      expect(items.length).to eq(3)
      expect(items[0].content).to eq('Step 1')
      expect(items[0].status).to eq('pending')
      expect(items[1].content).to eq('Step 2')
      expect(items[1].status).to eq('completed')
    end

    it 'skips empty content' do
      markdown = "- [ ] \n- [x] Real task"
      items = described_class.extract_plan_todos(
        markdown: markdown,
        plan_id: 'p1',
        relative_path: '.dfsdd/plan/f.md',
        now: '2024-01-01T00:00:00Z'
      )
      expect(items.length).to eq(1)
      expect(items[0].content).to eq('Real task')
    end

    it 'returns empty array when no tasks' do
      items = described_class.extract_plan_todos(
        markdown: '# No tasks here',
        plan_id: 'p1',
        relative_path: '.dfsdd/plan/f.md',
        now: '2024-01-01T00:00:00Z'
      )
      expect(items).to eq([])
    end
  end

  describe '.patch_plan_todo_status' do
    it 'patches a task from unchecked to checked' do
      markdown = "- [ ] Step 1\n- [ ] Step 2"
      source = DeepForge::Contracts::ThreadTodoSource.new(
        kind: 'plan', plan_id: 'p1', relative_path: '.dfsdd/plan/f.md',
        ordinal: 0, content_hash: described_class.todo_content_hash('Step 1')
      )
      item = DeepForge::Contracts::ThreadTodoItem.new(
        id: 'todo_1', content: 'Step 1', status: 'completed',
        source: source, created_at: '2024-01-01', updated_at: '2024-01-01'
      )

      result = described_class.patch_plan_todo_status(markdown, item)
      expect(result[:changed]).to be true
      expect(result[:markdown]).to include('- [x] Step 1')
      expect(result[:markdown]).to include('- [ ] Step 2')
    end

    it 'returns unchanged when source is not plan' do
      markdown = '- [ ] Step 1'
      item = DeepForge::Contracts::ThreadTodoItem.new(
        id: 'todo_1', content: 'Step 1', status: 'completed',
        source: nil, created_at: '2024-01-01', updated_at: '2024-01-01'
      )

      result = described_class.patch_plan_todo_status(markdown, item)
      expect(result[:changed]).to be false
    end
  end

  describe '.source_key' do
    it 'builds a key from source' do
      source = DeepForge::Contracts::ThreadTodoSource.new(
        kind: 'plan', plan_id: 'p1', relative_path: '.dfsdd/plan/f.md',
        ordinal: 0, content_hash: 'abc'
      )
      key = described_class.source_key(source)
      expect(key).to eq('plan:p1:.dfsdd/plan/f.md:0:abc')
    end
  end

  describe '.normalize_plan_relative_path' do
    it 'normalizes backslashes' do
      expect(described_class.normalize_plan_relative_path('.dfsdd\\plan\\f.md')).to eq('.dfsdd/plan/f.md')
    end

    it 'removes leading ./' do
      expect(described_class.normalize_plan_relative_path('./.dfsdd/plan/f.md')).to eq('.dfsdd/plan/f.md')
    end

    it 'collapses multiple slashes' do
      expect(described_class.normalize_plan_relative_path('.dfsdd//plan///f.md')).to eq('.dfsdd/plan/f.md')
    end
  end
end
