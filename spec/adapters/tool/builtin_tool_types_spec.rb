# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/builtin_tool_types'

RSpec.describe DeepForge::Adapters::Tool do
  describe 'constants' do
    it 'defines DEFAULT_BASH_TIMEOUT_SECONDS' do
      expect(described_class::DEFAULT_BASH_TIMEOUT_SECONDS).to eq(120)
    end

    it 'defines DEFAULT_SEARCH_LIMIT' do
      expect(described_class::DEFAULT_SEARCH_LIMIT).to eq(100)
    end

    it 'defines DEFAULT_LIST_LIMIT' do
      expect(described_class::DEFAULT_LIST_LIMIT).to eq(500)
    end

    it 'defines DEFAULT_FIND_LIMIT' do
      expect(described_class::DEFAULT_FIND_LIMIT).to eq(1000)
    end

    it 'defines DEFAULT_IMAGE_MAX_DIMENSION' do
      expect(described_class::DEFAULT_IMAGE_MAX_DIMENSION).to eq(2000)
    end

    it 'defines DEFAULT_IMAGE_MAX_BASE64_BYTES' do
      expect(described_class::DEFAULT_IMAGE_MAX_BASE64_BYTES).to eq(4.5 * 1024 * 1024)
    end

    it 'defines FD_EXECUTABLE_CANDIDATES as frozen array' do
      expect(described_class::FD_EXECUTABLE_CANDIDATES).to be_frozen
      expect(described_class::FD_EXECUTABLE_CANDIDATES).to include('fd')
    end

    it 'defines RG_EXECUTABLE_CANDIDATES as frozen array' do
      expect(described_class::RG_EXECUTABLE_CANDIDATES).to be_frozen
      expect(described_class::RG_EXECUTABLE_CANDIDATES).to include('rg')
    end

    it 'defines COMPACT_RESOURCE_FILE_NAMES as frozen set' do
      expect(described_class::COMPACT_RESOURCE_FILE_NAMES).to be_a(Set)
      expect(described_class::COMPACT_RESOURCE_FILE_NAMES).to include('CLAUDE.md')
    end

    it 'defines ALL_BUILTIN_TOOL_NAMES' do
      expect(described_class::ALL_BUILTIN_TOOL_NAMES).to be_a(Set)
      expect(described_class::ALL_BUILTIN_TOOL_NAMES).to include('read', 'bash', 'edit', 'write', 'grep', 'find', 'ls')
    end

    it 'defines ALL_TOOL_NAMES as alias for ALL_BUILTIN_TOOL_NAMES' do
      expect(described_class::ALL_TOOL_NAMES).to equal(described_class::ALL_BUILTIN_TOOL_NAMES)
    end
  end

  describe 'struct types' do
    it 'defines TextSlice with expected fields' do
      ts = described_class::TextSlice.new(text: 'hello', truncated: false)
      expect(ts.text).to eq('hello')
      expect(ts.truncated).to be false
    end

    it 'defines ShellConfig' do
      sc = described_class::ShellConfig.new(shell: '/bin/bash', args: ['-lc'])
      expect(sc.shell).to eq('/bin/bash')
      expect(sc.args).to eq(['-lc'])
    end

    it 'defines ListEntry' do
      le = described_class::ListEntry.new(path: '/a', relative_path: 'a', name: 'a', kind: 'file', size: 100)
      expect(le.kind).to eq('file')
    end

    it 'defines GrepMatch' do
      gm = described_class::GrepMatch.new(path: '/a', relative_path: 'a', line: 1, column: 1, text: 'hi')
      expect(gm.line).to eq(1)
    end

    it 'defines EditInstruction' do
      ei = described_class::EditInstruction.new(old_text: 'a', new_text: 'b')
      expect(ei.old_text).to eq('a')
    end

    it 'defines ImageDetection' do
      id = described_class::ImageDetection.new(mime_type: 'image/png', width: 100, height: 200)
      expect(id.mime_type).to eq('image/png')
    end

    it 'defines ReadClassification' do
      rc = described_class::ReadClassification.new(kind: 'skill', label: 'test')
      expect(rc.kind).to eq('skill')
    end

    it 'defines ReadLocalToolOptions' do
      opts = described_class::ReadLocalToolOptions.new(max_lines: 500)
      expect(opts.max_lines).to eq(500)
    end

    it 'defines BuiltinLocalToolsOptions' do
      opts = described_class::BuiltinLocalToolsOptions.new
      expect(opts.read).to be_nil
      expect(opts.bash).to be_nil
    end

    it 'defines ToolsOptions as alias for BuiltinLocalToolsOptions' do
      expect(described_class::ToolsOptions).to equal(described_class::BuiltinLocalToolsOptions)
    end
  end
end
