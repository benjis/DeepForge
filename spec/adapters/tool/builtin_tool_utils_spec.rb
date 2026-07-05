# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_tool_types'
require_relative '../../../lib/deepforge/adapters/tool/builtin_read_tool'
require_relative '../../../lib/deepforge/adapters/tool/builtin_tool_utils'

RSpec.describe DeepForge::Adapters::Tool::BuiltinToolUtils do
  describe '.with_tool_boundary' do
    it 'returns the block result on success' do
      result = described_class.with_tool_boundary { { output: 'ok' } }
      expect(result).to eq({ output: 'ok' })
    end

    it 'catches errors and returns error output' do
      result = described_class.with_tool_boundary { raise 'something broke' }
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to eq('something broke')
    end

    it 'catches StandardError subclasses' do
      result = described_class.with_tool_boundary { raise ArgumentError, 'bad arg' }
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to eq('bad arg')
    end
  end

  describe '.workspace_root' do
    it 'returns pwd for nil workspace' do
      expect(described_class.workspace_root(nil)).to eq(Dir.pwd)
    end

    it 'returns pwd for empty workspace' do
      expect(described_class.workspace_root('')).to eq(Dir.pwd)
    end

    it 'returns pwd for whitespace-only workspace' do
      expect(described_class.workspace_root('  ')).to eq(Dir.pwd)
    end

    it 'returns absolute path for valid workspace' do
      expect(described_class.workspace_root('/tmp')).to eq('/tmp')
    end
  end

  describe '.binary_buffer?' do
    it 'returns true for buffer containing null byte' do
      expect(described_class.binary_buffer?("hello\x00world")).to be true
    end

    it 'returns false for plain text buffer' do
      expect(described_class.binary_buffer?('hello world')).to be false
    end

    it 'returns false for empty buffer' do
      expect(described_class.binary_buffer?('')).to be false
    end
  end

  describe '.detect_image_mime_type' do
    it 'returns nil for non-image data' do
      expect(described_class.detect_image_mime_type('just text')).to be_nil
    end

    it 'detects GIF format' do
      gif_header = 'GIF89a'.b + ([0] * 10).pack('C*')
      result = described_class.detect_image_mime_type(gif_header)
      expect(result).not_to be_nil
      expect(result.mime_type).to eq('image/gif')
    end

    it 'detects WebP format' do
      webp_header = 'RIFF'.b + [0, 0, 0, 0].pack('C*') + 'WEBP'.b + ([0] * 10).pack('C*')
      result = described_class.detect_image_mime_type(webp_header)
      expect(result).not_to be_nil
      expect(result.mime_type).to eq('image/webp')
    end

    it 'returns nil for non-image buffer' do
      expect(described_class.detect_image_mime_type('not an image')).to be_nil
    end

    it 'returns nil for short buffer' do
      expect(described_class.detect_image_mime_type('ab')).to be_nil
    end
  end

  describe '.normalize_positive_integer' do
    it 'returns value for positive integers' do
      expect(described_class.normalize_positive_integer(5, 10)).to eq(5)
    end

    it 'returns fallback for nil' do
      expect(described_class.normalize_positive_integer(nil, 10)).to eq(10)
    end

    it 'returns fallback for zero' do
      expect(described_class.normalize_positive_integer(0, 10)).to eq(10)
    end

    it 'returns fallback for negative' do
      expect(described_class.normalize_positive_integer(-1, 10)).to eq(10)
    end

    it 'returns fallback for non-finite' do
      expect(described_class.normalize_positive_integer(Float::NAN, 10)).to eq(10)
    end
  end

  describe '.normalize_boolean' do
    it 'returns true for true' do
      expect(described_class.normalize_boolean(true)).to be true
    end

    it 'returns false for false' do
      expect(described_class.normalize_boolean(false)).to be false
    end

    it 'returns fallback for non-boolean' do
      expect(described_class.normalize_boolean('yes')).to be false
      expect(described_class.normalize_boolean('yes', true)).to be true
    end
  end

  describe '.glob_to_regexp' do
    it 'converts simple glob' do
      re = described_class.glob_to_regexp('*.rb')
      expect(re).to match('test.rb')
      expect(re).not_to match('test.py')
    end

    it 'converts double star glob' do
      re = described_class.glob_to_regexp('**/*.rb')
      expect(re).to match('test.rb')
      expect(re).to match('src/test.rb')
      expect(re).not_to match('test.py')
    end

    it 'converts question mark glob' do
      re = described_class.glob_to_regexp('test?.rb')
      expect(re).to match('test1.rb')
      expect(re).not_to match('test12.rb')
    end
  end

  describe '.normalize_tool_path' do
    it 'converts backslashes to forward slashes' do
      expect(described_class.normalize_tool_path('path\\to\\file')).to eq('path/to/file')
    end

    it 'leaves forward slashes unchanged' do
      expect(described_class.normalize_tool_path('path/to/file')).to eq('path/to/file')
    end
  end

  describe '.parse_edit_instructions' do
    it 'parses old_text/new_text from args' do
      args = { old_text: 'a', new_text: 'b' }
      result = described_class.parse_edit_instructions(args)
      expect(result.length).to eq(1)
      expect(result.first.old_text).to eq('a')
      expect(result.first.new_text).to eq('b')
    end

    it 'parses edits array' do
      args = { edits: [{ old_text: 'a', new_text: 'b' }, { old_text: 'c', new_text: 'd' }] }
      result = described_class.parse_edit_instructions(args)
      expect(result.length).to eq(2)
    end

    it 'returns empty array for invalid args' do
      expect(described_class.parse_edit_instructions({})).to eq([])
      expect(described_class.parse_edit_instructions({ old_text: 'a' })).to eq([])
    end
  end

  describe '.find_occurrences' do
    it 'finds all occurrences' do
      result = described_class.find_occurrences('hello hello hello', 'hello')
      expect(result).to eq([0, 6, 12])
    end

    it 'returns empty for no matches' do
      expect(described_class.find_occurrences('hello', 'xyz')).to eq([])
    end

    it 'returns empty for empty needle' do
      expect(described_class.find_occurrences('hello', '')).to eq([])
    end
  end

  describe '.apply_exact_text_edits' do
    it 'applies a single edit' do
      result = described_class.apply_exact_text_edits('hello world', [
                                                        DeepForge::Adapters::Tool::EditInstruction.new(old_text: 'world', new_text: 'ruby')
                                                      ])
      expect(result[:next]).to eq('hello ruby')
      expect(result[:replacements]).to eq(1)
    end

    it 'applies multiple non-overlapping edits' do
      result = described_class.apply_exact_text_edits('aaa bbb ccc', [
                                                        DeepForge::Adapters::Tool::EditInstruction.new(old_text: 'aaa',
                                                                                                       new_text: '111'),
                                                        DeepForge::Adapters::Tool::EditInstruction.new(old_text: 'ccc',
                                                                                                       new_text: '333')
                                                      ])
      expect(result[:next]).to eq('111 bbb 333')
      expect(result[:replacements]).to eq(2)
    end

    it 'raises when old_text not found' do
      expect do
        described_class.apply_exact_text_edits('hello', [
                                                 DeepForge::Adapters::Tool::EditInstruction.new(old_text: 'xyz', new_text: '123')
                                               ])
      end.to raise_error(RuntimeError, /not found/)
    end

    it 'raises when old_text matches multiple locations' do
      expect do
        described_class.apply_exact_text_edits('aaa aaa aaa', [
                                                 DeepForge::Adapters::Tool::EditInstruction.new(old_text: 'aaa', new_text: '111')
                                               ])
      end.to raise_error(RuntimeError, /matched \d+ locations/)
    end
  end

  describe '.compile_pattern' do
    it 'compiles a regex pattern' do
      re = described_class.compile_pattern('hello', false)
      expect(re).to match('hello')
    end

    it 'compiles a literal pattern' do
      re = described_class.compile_pattern('hello.world', true)
      expect(re).to match('hello.world')
      expect(re).not_to match('helloXworld')
    end
  end

  describe '.collect_paths' do
    it 'collects files from a directory' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.txt'), 'a')
        File.write(File.join(dir, 'b.txt'), 'b')
        FileUtils.mkdir_p(File.join(dir, 'sub'))
        File.write(File.join(dir, 'sub', 'c.txt'), 'c')

        paths = described_class.collect_paths(dir)
        expect(paths.length).to eq(3)
      end
    end

    it 'respects limit' do
      Dir.mktmpdir do |dir|
        5.times { |i| File.write(File.join(dir, "f#{i}.txt"), 'x') }
        paths = described_class.collect_paths(dir, limit: 2)
        expect(paths.length).to eq(2)
      end
    end

    it 'includes directories when requested' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'sub'))
        File.write(File.join(dir, 'a.txt'), 'a')
        paths = described_class.collect_paths(dir, include_directories: true)
        expect(paths.any? { |p| File.directory?(p) }).to be true
      end
    end
  end

  describe '.list_directory' do
    it 'lists directory contents' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.txt'), 'a')
        FileUtils.mkdir_p(File.join(dir, 'sub'))
        entries = described_class.list_directory(dir, dir, false, 100)
        expect(entries.length).to eq(2)
        names = entries.map(&:name)
        expect(names).to include('a.txt', 'sub')
      end
    end

    it 'returns single entry for a file' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'a.txt')
        File.write(file, 'a')
        entries = described_class.list_directory(file, dir, false, 100)
        expect(entries.length).to eq(1)
        expect(entries.first.kind).to eq('file')
      end
    end
  end

  describe '.make_list_entry' do
    it 'creates entry for file' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'test.txt')
        File.write(file, 'hello')
        stat = File.lstat(file)
        entry = described_class.make_list_entry(file, dir, stat)
        expect(entry.kind).to eq('file')
        expect(entry.name).to eq('test.txt')
        expect(entry.size).to eq(5)
      end
    end

    it 'creates entry for directory' do
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, 'sub')
        FileUtils.mkdir_p(subdir)
        stat = File.lstat(subdir)
        entry = described_class.make_list_entry(subdir, dir, stat)
        expect(entry.kind).to eq('directory')
        expect(entry.name).to eq('sub')
      end
    end
  end

  describe '.get_read_classification' do
    it 'classifies SKILL.md files' do
      result = described_class.get_read_classification('/workspace/skills/test/SKILL.md', '/workspace')
      expect(result).not_to be_nil
      expect(result.kind).to eq('skill')
      expect(result.label).to eq('test')
    end

    it 'classifies CLAUDE.md files' do
      result = described_class.get_read_classification('/workspace/CLAUDE.md', '/workspace')
      expect(result).not_to be_nil
      expect(result.kind).to eq('resource')
    end

    it 'classifies README.md files' do
      result = described_class.get_read_classification('/workspace/README.md', '/workspace')
      expect(result).not_to be_nil
      expect(result.kind).to eq('docs')
    end

    it 'returns nil for regular files' do
      result = described_class.get_read_classification('/workspace/src/main.rb', '/workspace')
      expect(result).to be_nil
    end
  end

  describe '.format_dimension_note' do
    it 'returns note for resized image' do
      img = DeepForge::Adapters::Tool::ResizedImageResult.new(
        width: 100, height: 100, original_width: 200, original_height: 200, was_resized: true
      )
      note = described_class.format_dimension_note(img)
      expect(note).to include('200x200')
      expect(note).to include('100x100')
    end

    it 'returns nil for non-resized image' do
      img = DeepForge::Adapters::Tool::ResizedImageResult.new(
        width: 100, height: 100, original_width: 100, original_height: 100, was_resized: false
      )
      expect(described_class.format_dimension_note(img)).to be_nil
    end
  end

  describe '.describe_kind' do
    it 'returns first for head mode' do
      expect(described_class.describe_kind('head')).to eq('first')
    end

    it 'returns last for other mode' do
      expect(described_class.describe_kind('tail')).to eq('last')
    end
  end

  describe '.shell_config' do
    it 'returns a ShellConfig' do
      config = described_class.shell_config
      expect(config).to be_a(DeepForge::Adapters::Tool::ShellConfig)
      expect(config.shell).not_to be_nil
      expect(config.args).to include('-lc')
    end
  end
end
