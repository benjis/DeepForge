# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_read_tool'

RSpec.describe DeepForge::Adapters::Tool::BuiltinReadTool do
  let(:workspace) { Dir.mktmpdir('deepforge-test') }

  after { FileUtils.remove_entry(workspace) }

  describe '.create' do
    it 'returns a read tool definition' do
      tool = described_class.create(nil)
      expect(tool[:name]).to eq('read')
      expect(tool[:description]).to include('file')
      expect(tool[:input_schema][:required]).to include('path')
      expect(tool[:policy]).to eq('auto')
    end

    it 'accepts custom options' do
      opts = described_class::ReadToolOptions.new(max_lines: 100)
      tool = described_class.create(opts)
      expect(tool[:name]).to eq('read')
    end
  end

  describe '.execute_read' do
    it 'reads a text file' do
      File.write(File.join(workspace, 'test.txt'), "hello\nworld")
      options = described_class::ReadToolOptions.new
      result = described_class.execute_read(
        { path: 'test.txt' },
        { workspace: workspace },
        options
      )
      expect(result[:output][:content]).to include('hello')
      expect(result[:output][:total_lines]).to eq(2)
    end

    it 'returns error for empty path' do
      options = described_class::ReadToolOptions.new
      result = described_class.execute_read(
        { path: '' },
        { workspace: workspace },
        options
      )
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('path is required')
    end

    it 'returns error for nonexistent file' do
      options = described_class::ReadToolOptions.new
      result = described_class.execute_read(
        { path: 'nonexistent.txt' },
        { workspace: workspace },
        options
      )
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('failed to read file')
    end

    it 'supports offset and limit' do
      lines = (1..20).map { |i| "line#{i}" }.join("\n")
      File.write(File.join(workspace, 'lines.txt'), lines)
      options = described_class::ReadToolOptions.new
      result = described_class.execute_read(
        { path: 'lines.txt', offset: 5, limit: 3 },
        { workspace: workspace },
        options
      )
      expect(result[:output][:content]).to include('line5')
      expect(result[:output][:content]).to include('line7')
      expect(result[:output][:content]).not_to include('line4')
    end

    it 'returns error for binary file' do
      File.binwrite(File.join(workspace, 'binary.bin'), "hello\x00world")
      options = described_class::ReadToolOptions.new
      result = described_class.execute_read(
        { path: 'binary.bin' },
        { workspace: workspace },
        options
      )
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('text files')
    end
  end

  describe '.detect_image' do
    it 'detects PNG' do
      png_header = ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + ([0] * 20)).pack('C*')
      result = described_class.detect_image(png_header)
      expect(result).not_to be_nil
      expect(result[:mime_type]).to eq('image/png')
    end

    it 'detects JPEG' do
      jpeg_header = ([0xFF, 0xD8, 0xFF] + ([0] * 10)).pack('C*')
      result = described_class.detect_image(jpeg_header)
      expect(result).not_to be_nil
      expect(result[:mime_type]).to eq('image/jpeg')
    end

    it 'detects GIF' do
      gif_header = 'GIF89a'.b + ("\x00" * 10)
      result = described_class.detect_image(gif_header)
      expect(result).not_to be_nil
      expect(result[:mime_type]).to eq('image/gif')
    end

    it 'detects WebP' do
      webp_header = "RIFF\x00\x00\x00\x00WEBP".b + ("\x00" * 10)
      result = described_class.detect_image(webp_header)
      expect(result).not_to be_nil
      expect(result[:mime_type]).to eq('image/webp')
    end

    it 'returns nil for non-image' do
      expect(described_class.detect_image('not an image')).to be_nil
    end

    it 'returns nil for short buffer' do
      expect(described_class.detect_image('ab')).to be_nil
    end
  end

  describe '.binary_buffer?' do
    it 'returns true for binary content' do
      expect(described_class.binary_buffer?("hello\x00world")).to be true
    end

    it 'returns false for text content' do
      expect(described_class.binary_buffer?('hello world')).to be false
    end
  end

  describe '.truncate_head' do
    it 'returns unchanged when within limits' do
      result = described_class.truncate_head('hello', 10, 1000)
      expect(result[:truncated]).to be false
      expect(result[:content]).to eq('hello')
    end

    it 'truncates when exceeding limits' do
      text = (1..100).map { |i| "line#{i}" }.join("\n")
      result = described_class.truncate_head(text, 5, 100_000)
      expect(result[:truncated]).to be true
      expect(result[:output_lines]).to eq(5)
    end
  end

  describe '.format_size' do
    it 'formats bytes' do
      expect(described_class.format_size(500)).to eq('500 B')
    end

    it 'formats KB' do
      expect(described_class.format_size(1536)).to eq('1.5 KB')
    end

    it 'formats MB' do
      expect(described_class.format_size(2 * 1024 * 1024)).to eq('2.0 MB')
    end
  end

  describe '.normalize_positive_integer' do
    it 'returns default for nil' do
      expect(described_class.normalize_positive_integer(nil, 10)).to eq(10)
    end

    it 'returns positive value' do
      expect(described_class.normalize_positive_integer(5, 10)).to eq(5)
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
