# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/edit_diff'

RSpec.describe DeepForge::Adapters::Tool::EditDiff do
  describe '.detect_line_ending' do
    it 'detects CRLF' do
      expect(described_class.detect_line_ending("hello\r\nworld")).to eq("\r\n")
    end

    it 'detects LF' do
      expect(described_class.detect_line_ending("hello\nworld")).to eq("\n")
    end

    it 'returns LF for empty string' do
      expect(described_class.detect_line_ending('')).to eq("\n")
    end
  end

  describe '.normalize_to_lf' do
    it 'converts CRLF to LF' do
      expect(described_class.normalize_to_lf("hello\r\nworld")).to eq("hello\nworld")
    end

    it 'converts CR to LF' do
      expect(described_class.normalize_to_lf("hello\rworld")).to eq("hello\nworld")
    end

    it 'leaves LF unchanged' do
      expect(described_class.normalize_to_lf("hello\nworld")).to eq("hello\nworld")
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

  describe '.strip_bom' do
    it 'strips BOM when present' do
      result = described_class.strip_bom("\uFEFFhello")
      expect(result[:bom]).to eq("\uFEFF")
      expect(result[:text]).to eq('hello')
    end

    it 'returns empty BOM when absent' do
      result = described_class.strip_bom('hello')
      expect(result[:bom]).to eq('')
      expect(result[:text]).to eq('hello')
    end
  end

  describe '.normalize_for_fuzzy_match' do
    it 'normalizes unicode quotes' do
      result = described_class.normalize_for_fuzzy_match("\u2018hello\u2019")
      expect(result).to eq("'hello'")
    end

    it 'normalizes unicode dashes' do
      result = described_class.normalize_for_fuzzy_match("hello\u2014world")
      expect(result).to eq('hello-world')
    end

    it 'normalizes non-breaking spaces' do
      result = described_class.normalize_for_fuzzy_match("hello\u00A0world")
      expect(result).to eq('hello world')
    end

    it 'strips trailing whitespace per line' do
      result = described_class.normalize_for_fuzzy_match("hello  \nworld  ")
      expect(result).to eq("hello\nworld")
    end
  end

  describe '.fuzzy_find_text' do
    it 'finds exact match' do
      result = described_class.fuzzy_find_text('hello world', 'hello')
      expect(result.found).to be true
      expect(result.used_fuzzy_match).to be false
      expect(result.index).to eq(0)
    end

    it 'finds fuzzy match' do
      result = described_class.fuzzy_find_text("hello\u00A0world", 'hello world')
      expect(result.found).to be true
      expect(result.used_fuzzy_match).to be true
    end

    it 'returns not found' do
      result = described_class.fuzzy_find_text('hello world', 'xyz')
      expect(result.found).to be false
      expect(result.index).to eq(-1)
    end
  end

  describe '.apply_edits_to_normalized_content' do
    it 'applies a single edit' do
      edit = DeepForge::Adapters::Tool::Edit.new(old_text: 'hello', new_text: 'goodbye')
      result = described_class.apply_edits_to_normalized_content('hello world', [edit], 'test.txt')
      expect(result.new_content).to eq('goodbye world')
    end

    it 'applies multiple non-overlapping edits' do
      edits = [
        DeepForge::Adapters::Tool::Edit.new(old_text: 'aaa', new_text: '111'),
        DeepForge::Adapters::Tool::Edit.new(old_text: 'ccc', new_text: '333')
      ]
      result = described_class.apply_edits_to_normalized_content('aaa bbb ccc', edits, 'test.txt')
      expect(result.new_content).to eq('111 bbb 333')
    end

    it 'raises on empty old text' do
      edit = DeepForge::Adapters::Tool::Edit.new(old_text: '', new_text: 'b')
      expect do
        described_class.apply_edits_to_normalized_content('hello', [edit], 'test.txt')
      end.to raise_error(RuntimeError, /empty/)
    end

    it 'raises when text not found' do
      edit = DeepForge::Adapters::Tool::Edit.new(old_text: 'xyz', new_text: '123')
      expect do
        described_class.apply_edits_to_normalized_content('hello', [edit], 'test.txt')
      end.to raise_error(RuntimeError, /Could not find/)
    end

    it 'applies first occurrence when text has duplicates' do
      edit = DeepForge::Adapters::Tool::Edit.new(old_text: 'aaa', new_text: '111')
      result = described_class.apply_edits_to_normalized_content('aaa bbb aaa', [edit], 'test.txt')
      expect(result.new_content).to eq('111 bbb aaa')
    end

    it 'raises when no change produced' do
      edit = DeepForge::Adapters::Tool::Edit.new(old_text: 'hello', new_text: 'hello')
      expect do
        described_class.apply_edits_to_normalized_content('hello', [edit], 'test.txt')
      end.to raise_error(RuntimeError, /No changes/)
    end
  end

  describe '.first_changed_line' do
    it 'finds first changed line' do
      result = described_class.first_changed_line("a\nb\nc", "a\nx\nc")
      expect(result).to eq(2)
    end

    it 'returns nil for identical content' do
      result = described_class.first_changed_line("a\nb", "a\nb")
      expect(result).to be_nil
    end
  end

  describe '.generate_display_diff' do
    it 'generates diff with line numbers' do
      diff = described_class.generate_display_diff("hello\n", "goodbye\n")
      expect(diff).to include('-')
      expect(diff).to include('+')
    end

    it 'shows unchanged lines for identical content' do
      diff = described_class.generate_display_diff("hello\n", "hello\n")
      expect(diff).to include('hello')
    end
  end

  describe '.generate_diff_string' do
    it 'returns EditDiffResult' do
      result = described_class.generate_diff_string("hello\n", "goodbye\n")
      expect(result).to be_a(DeepForge::Adapters::Tool::EditDiffResult)
      expect(result.diff).to include('-')
      expect(result.first_changed_line).to eq(1)
    end
  end

  describe '.compute_edits_diff' do
    it 'computes diff from file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test.txt')
        File.write(path, 'hello world')
        edit = DeepForge::Adapters::Tool::Edit.new(old_text: 'hello', new_text: 'goodbye')
        result = described_class.compute_edits_diff('test.txt', [edit], dir)
        expect(result).to be_a(DeepForge::Adapters::Tool::EditDiffResult)
        expect(result.diff).to include('-')
      end
    end

    it 'returns error for nonexistent file' do
      result = described_class.compute_edits_diff('missing.txt', [], '/tmp')
      expect(result).to be_a(DeepForge::Adapters::Tool::EditDiffError)
      expect(result.error).to include('No such file')
    end
  end

  describe '.compute_edit_diff' do
    it 'computes single edit diff' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test.txt')
        File.write(path, 'hello world')
        result = described_class.compute_edit_diff('test.txt', 'hello', 'goodbye', dir)
        expect(result).to be_a(DeepForge::Adapters::Tool::EditDiffResult)
      end
    end
  end
end
