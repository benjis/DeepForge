# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/mcp_tool_provider'

RSpec.describe DeepForge::Adapters::Tool::McpToolProvider do
  describe '.normalize_mcp_tool_name' do
    it 'normalizes tool name' do
      result = described_class.normalize_mcp_tool_name('my-server', 'my_tool')
      expect(result).to eq('mcp_my_server_my_tool')
    end

    it 'handles special characters' do
      result = described_class.normalize_mcp_tool_name('server@1', 'tool-name')
      expect(result).to eq('mcp_server_1_tool_name')
    end
  end

  describe '.slug' do
    it 'converts to slug' do
      expect(described_class.slug('My Tool')).to eq('my_tool')
    end

    it 'handles special characters' do
      expect(described_class.slug('tool-name@1.0')).to eq('tool_name_1_0')
    end

    it 'returns tool for empty' do
      expect(described_class.slug('')).to eq('tool')
    end
  end

  describe '.mcp_server_trusted?' do
    it 'returns true for user trust scope' do
      server = { trust_scope: 'user' }
      expect(described_class.mcp_server_trusted?(server, '/any/path')).to be true
    end

    it 'returns true when workspace is in trusted roots' do
      server = { trusted_workspace_roots: ['/workspace'] }
      expect(described_class.mcp_server_trusted?(server, '/workspace')).to be true
    end

    it 'returns true when workspace is subdirectory of trusted root' do
      server = { trusted_workspace_roots: ['/workspace'] }
      expect(described_class.mcp_server_trusted?(server, '/workspace/sub')).to be true
    end

    it 'returns false when workspace is not trusted' do
      server = { trusted_workspace_roots: ['/other'] }
      expect(described_class.mcp_server_trusted?(server, '/workspace')).to be false
    end
  end

  describe '.normalize_path_for_trust' do
    it 'converts backslashes' do
      expect(described_class.normalize_path_for_trust('path\\to\\dir')).to eq('path/to/dir')
    end

    it 'removes trailing slashes' do
      expect(described_class.normalize_path_for_trust('path/to/dir/')).to eq('path/to/dir')
    end
  end

  describe '.policy_from_annotations' do
    it 'returns auto for read-only' do
      annotations = { readOnlyHint: true }
      expect(described_class.policy_from_annotations(annotations)).to eq('auto')
    end

    it 'returns on-request for destructive' do
      annotations = { destructiveHint: true }
      expect(described_class.policy_from_annotations(annotations)).to eq('on-request')
    end

    it 'returns untrusted for open world' do
      annotations = { openWorldHint: true }
      expect(described_class.policy_from_annotations(annotations)).to eq('untrusted')
    end

    it 'returns on-request for nil annotations' do
      expect(described_class.policy_from_annotations(nil)).to eq('on-request')
    end
  end

  describe '.catalog_fingerprint' do
    it 'generates a fingerprint' do
      fp = described_class.catalog_fingerprint(%w[tool1 tool2])
      expect(fp).to be_a(String)
      expect(fp.length).to eq(16)
    end

    it 'is consistent for same input' do
      fp1 = described_class.catalog_fingerprint(%w[a b])
      fp2 = described_class.catalog_fingerprint(%w[a b])
      expect(fp1).to eq(fp2)
    end

    it 'differs for different input' do
      fp1 = described_class.catalog_fingerprint(['a'])
      fp2 = described_class.catalog_fingerprint(['b'])
      expect(fp1).not_to eq(fp2)
    end
  end

  describe '.parse_tool_descriptor' do
    it 'parses tool data' do
      data = {
        'name' => 'test_tool',
        'title' => 'Test',
        'description' => 'A test tool',
        'inputSchema' => { type: 'object' }
      }
      result = described_class.parse_tool_descriptor(data)
      expect(result).to be_a(DeepForge::Adapters::Tool::McpToolProvider::McpToolDescriptor)
      expect(result.name).to eq('test_tool')
      expect(result.description).to eq('A test tool')
    end
  end

  describe '.build' do
    it 'returns empty result when config disabled' do
      config = { enabled: false }
      result = described_class.build(config, described_class::McpToolProviderOptions.new)
      expect(result.providers).to be_empty
      expect(result.tool_count).to eq(0)
    end

    it 'returns empty result when config is nil' do
      result = described_class.build(nil, described_class::McpToolProviderOptions.new)
      expect(result.providers).to be_empty
    end

    it 'returns empty result when no servers' do
      config = { enabled: true, servers: {} }
      result = described_class.build(config, described_class::McpToolProviderOptions.new)
      expect(result.providers).to be_empty
    end

    it 'skips disabled servers' do
      config = {
        enabled: true,
        servers: {
          'disabled_server' => { enabled: false, transport: 'stdio' }
        }
      }
      result = described_class.build(config, described_class::McpToolProviderOptions.new)
      expect(result.providers).to be_empty
      expect(result.diagnostics.length).to eq(1)
      expect(result.diagnostics.first.status).to eq('disabled')
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
