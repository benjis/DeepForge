# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_file_tools'

RSpec.describe DeepForge::Adapters::Tool::BuiltinFileTools do
  let(:workspace) { Dir.mktmpdir('deepforge-test') }

  after { FileUtils.remove_entry(workspace) }

  describe '.create_write_tool' do
    it 'returns a write tool definition' do
      tool = described_class.create_write_tool(nil)
      expect(tool[:name]).to eq('write')
      expect(tool[:description]).to include('file')
      expect(tool[:input_schema][:required]).to include('path', 'content')
    end

    it 'accepts custom options' do
      opts = described_class::WriteLocalToolOptions.new
      tool = described_class.create_write_tool(opts)
      expect(tool[:name]).to eq('write')
    end
  end

  describe '.create_edit_tool' do
    it 'returns an edit tool definition' do
      tool = described_class.create_edit_tool(nil)
      expect(tool[:name]).to eq('edit')
      expect(tool[:description]).to include('edit')
      expect(tool[:input_schema][:required]).to include('path')
    end
  end

  describe '.execute_write' do
    it 'writes a file successfully' do
      mkdir_op = ->(path) { FileUtils.mkdir_p(path) }
      write_op = ->(path, content) { File.write(path, content) }
      context = { workspace: workspace }

      result = described_class.execute_write(
        { path: 'test.txt', content: 'hello' }, context, mkdir_op, write_op
      )
      expect(result[:output][:bytes_written]).to eq(5)
      expect(File.read(File.join(workspace, 'test.txt'))).to eq('hello')
    end

    it 'returns error for empty path' do
      mkdir_op = ->(path) { FileUtils.mkdir_p(path) }
      write_op = ->(path, content) { File.write(path, content) }
      result = described_class.execute_write(
        { path: '', content: 'hello' }, { workspace: workspace }, mkdir_op, write_op
      )
      expect(result[:is_error]).to be true
    end

    it 'returns error for nil content' do
      mkdir_op = ->(path) { FileUtils.mkdir_p(path) }
      write_op = ->(path, content) { File.write(path, content) }
      result = described_class.execute_write(
        { path: 'test.txt', content: nil }, { workspace: workspace }, mkdir_op, write_op
      )
      expect(result[:is_error]).to be true
    end

    it 'creates parent directories' do
      mkdir_op = ->(path) { FileUtils.mkdir_p(path) }
      write_op = ->(path, content) { File.write(path, content) }
      context = { workspace: workspace }

      result = described_class.execute_write(
        { path: 'sub/dir/test.txt', content: 'hello' }, context, mkdir_op, write_op
      )
      expect(result[:output][:bytes_written]).to eq(5)
      expect(File.exist?(File.join(workspace, 'sub/dir/test.txt'))).to be true
    end
  end

  describe '.execute_edit' do
    it 'edits a file successfully' do
      File.write(File.join(workspace, 'test.txt'), 'hello world')

      read_op = ->(path) { File.read(path) }
      write_op = ->(path, content) { File.write(path, content) }
      context = { workspace: workspace }

      result = described_class.execute_edit(
        { path: 'test.txt', old_text: 'hello', new_text: 'goodbye' },
        context, read_op, write_op
      )
      expect(result[:output][:replacements]).to eq(1)
      expect(File.read(File.join(workspace, 'test.txt'))).to eq('goodbye world')
    end

    it 'returns error for empty path' do
      read_op = ->(path) { File.read(path) }
      write_op = ->(path, content) { File.write(path, content) }
      result = described_class.execute_edit(
        { path: '', old_text: 'a', new_text: 'b' },
        { workspace: workspace }, read_op, write_op
      )
      expect(result[:is_error]).to be true
    end

    it 'returns error for no edits' do
      read_op = ->(path) { File.read(path) }
      write_op = ->(path, content) { File.write(path, content) }
      result = described_class.execute_edit(
        { path: 'test.txt' },
        { workspace: workspace }, read_op, write_op
      )
      expect(result[:is_error]).to be true
    end

    it 'supports multiple edits' do
      File.write(File.join(workspace, 'test.txt'), 'aaa bbb ccc')

      read_op = ->(path) { File.read(path) }
      write_op = ->(path, content) { File.write(path, content) }
      context = { workspace: workspace }

      result = described_class.execute_edit(
        { path: 'test.txt', edits: [
          { old_text: 'aaa', new_text: '111' },
          { old_text: 'ccc', new_text: '333' }
        ] },
        context, read_op, write_op
      )
      expect(result[:output][:replacements]).to eq(2)
      expect(File.read(File.join(workspace, 'test.txt'))).to eq('111 bbb 333')
    end
  end

  describe '.parse_edit_instructions' do
    it 'parses old_text/new_text' do
      result = described_class.parse_edit_instructions({ old_text: 'a', new_text: 'b' })
      expect(result.length).to eq(1)
      expect(result.first[:old_text]).to eq('a')
    end

    it 'parses edits array' do
      result = described_class.parse_edit_instructions({
                                                         edits: [{ old_text: 'a', new_text: 'b' },
                                                                 { old_text: 'c', new_text: 'd' }]
                                                       })
      expect(result.length).to eq(2)
    end

    it 'returns empty for invalid input' do
      expect(described_class.parse_edit_instructions({})).to eq([])
    end
  end

  describe '.apply_edits' do
    it 'applies a single edit' do
      result = described_class.apply_edits('hello world', [{ old_text: 'hello', new_text: 'goodbye' }], 'test.txt')
      expect(result).to eq('goodbye world')
    end

    it 'raises when edit text not found' do
      expect do
        described_class.apply_edits('hello', [{ old_text: 'xyz', new_text: '123' }], 'test.txt')
      end.to raise_error(RuntimeError, /edit text not found/)
    end
  end

  describe '.detect_line_ending' do
    it 'detects CRLF' do
      expect(described_class.detect_line_ending("hello\r\nworld")).to eq("\r\n")
    end

    it 'detects LF' do
      expect(described_class.detect_line_ending("hello\nworld")).to eq("\n")
    end

    it 'detects CR only' do
      expect(described_class.detect_line_ending("hello\rworld")).to eq("\r")
    end
  end

  describe '.restore_line_endings' do
    it 'restores CRLF' do
      result = described_class.restore_line_endings("hello\nworld", "\r\n")
      expect(result).to eq("hello\r\nworld")
    end

    it 'leaves LF unchanged' do
      result = described_class.restore_line_endings("hello\nworld", "\n")
      expect(result).to eq("hello\nworld")
    end
  end

  describe '.generate_display_diff' do
    it 'generates diff for changed content' do
      diff = described_class.generate_display_diff("hello\n", "goodbye\n")
      expect(diff).to include('-')
      expect(diff).to include('+')
    end

    it 'returns empty for identical content' do
      diff = described_class.generate_display_diff("hello\n", "hello\n")
      expect(diff).to eq('')
    end
  end

  describe '.generate_unified_patch' do
    it 'generates unified patch' do
      patch = described_class.generate_unified_patch('test.txt', "hello\n", "goodbye\n")
      expect(patch).to include('--- a/test.txt')
      expect(patch).to include('+++ b/test.txt')
      expect(patch).to include('@@')
    end

    it 'returns only header for identical content' do
      patch = described_class.generate_unified_patch('test.txt', "hello\n", "hello\n")
      expect(patch).to include('--- a/test.txt')
      expect(patch).to include('+++ b/test.txt')
    end
  end

  describe '.first_changed_line' do
    it 'finds the first changed line' do
      result = described_class.first_changed_line("a\nb\nc", "a\nx\nc")
      expect(result).to eq(2)
    end

    it 'returns nil for identical content' do
      result = described_class.first_changed_line("a\nb", "a\nb")
      expect(result).to be_nil
    end
  end

  describe '.resolve_workspace_path' do
    it 'resolves relative path' do
      result = described_class.resolve_workspace_path('test.txt', { workspace: workspace })
      expect(result).to eq(File.join(workspace, 'test.txt'))
    end

    it 'returns absolute path as-is' do
      result = described_class.resolve_workspace_path('/tmp/test.txt', { workspace: workspace })
      expect(result).to eq('/tmp/test.txt')
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
