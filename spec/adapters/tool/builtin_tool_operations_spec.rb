# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_tool_operations'

RSpec.describe DeepForge::Adapters::Tool::BuiltinToolOperations do
  describe '.image_extension' do
    it 'returns png for image/png' do
      expect(described_class.image_extension('image/png')).to eq('png')
    end

    it 'returns jpg for image/jpeg' do
      expect(described_class.image_extension('image/jpeg')).to eq('jpg')
    end

    it 'returns gif for image/gif' do
      expect(described_class.image_extension('image/gif')).to eq('gif')
    end

    it 'returns webp for image/webp' do
      expect(described_class.image_extension('image/webp')).to eq('webp')
    end

    it 'returns img for unknown types' do
      expect(described_class.image_extension('image/bmp')).to eq('img')
    end
  end

  describe '.default_read_local_tool_operations' do
    it 'returns a ReadLocalToolOperations struct' do
      ops = described_class.default_read_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::ReadLocalToolOperations)
      expect(ops.stat).to be_a(Proc)
      expect(ops.read_file).to be_a(Proc)
      expect(ops.detect_image_mime_type).to be_a(Method)
      expect(ops.resize_image).to(satisfy { |m| m.is_a?(Proc) || m.is_a?(Method) })
    end
  end

  describe '.create_local_bash_operations' do
    it 'returns a BashLocalToolOperations struct' do
      ops = described_class.create_local_bash_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::BashLocalToolOperations)
      expect(ops.exec).to be_a(Proc)
    end
  end

  describe '.default_write_local_tool_operations' do
    it 'returns a WriteLocalToolOperations struct' do
      ops = described_class.default_write_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::WriteLocalToolOperations)
      expect(ops.mkdir).to be_a(Proc)
      expect(ops.write_file).to be_a(Proc)
    end

    it 'mkdir creates directories' do
      ops = described_class.default_write_local_tool_operations
      Dir.mktmpdir do |dir|
        new_dir = File.join(dir, 'sub', 'deep')
        ops.mkdir.call(new_dir)
        expect(Dir.exist?(new_dir)).to be true
      end
    end

    it 'write_file writes content' do
      ops = described_class.default_write_local_tool_operations
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test.txt')
        ops.write_file.call(path, 'hello')
        expect(File.read(path)).to eq('hello')
      end
    end
  end

  describe '.default_edit_local_tool_operations' do
    it 'returns an EditLocalToolOperations struct' do
      ops = described_class.default_edit_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::EditLocalToolOperations)
      expect(ops.read_file).to be_a(Proc)
      expect(ops.write_file).to be_a(Proc)
    end
  end

  describe '.default_find_local_tool_operations' do
    it 'returns a FindLocalToolOperations struct' do
      ops = described_class.default_find_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::FindLocalToolOperations)
    end
  end

  describe '.default_grep_local_tool_operations' do
    it 'returns a GrepLocalToolOperations struct' do
      ops = described_class.default_grep_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::GrepLocalToolOperations)
    end
  end

  describe '.default_ls_local_tool_operations' do
    it 'returns an LsLocalToolOperations struct' do
      ops = described_class.default_ls_local_tool_operations
      expect(ops).to be_a(DeepForge::Adapters::Tool::LsLocalToolOperations)
      expect(ops.stat).to be_a(Proc)
      expect(ops.readdir).to be_a(Proc)
    end

    it 'readdir lists entries' do
      ops = described_class.default_ls_local_tool_operations
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.txt'), 'a')
        entries = ops.readdir.call(dir)
        expect(entries.length).to eq(1)
        expect(entries.first[:name]).to eq('a.txt')
      end
    end
  end

  describe '.detect_image_mime_type_from_buffer' do
    it 'returns nil for non-image' do
      expect(described_class.detect_image_mime_type_from_buffer('text')).to be_nil
    end
  end
end
