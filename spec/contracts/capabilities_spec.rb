# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'capability status constants' do
    it 'defines AVAILABLE, DISABLED, UNAVAILABLE' do
      expect(described_class::RuntimeCapabilityStatus::AVAILABLE).to eq('available')
      expect(described_class::RuntimeCapabilityStatus::DISABLED).to eq('disabled')
      expect(described_class::RuntimeCapabilityStatus::UNAVAILABLE).to eq('unavailable')
    end
  end

  describe 'MCP transport kind constants' do
    it 'defines STDIO, STREAMABLE_HTTP, SSE' do
      expect(described_class::McpTransportKind::STDIO).to eq('stdio')
      expect(described_class::McpTransportKind::STREAMABLE_HTTP).to eq('streamable-http')
      expect(described_class::McpTransportKind::SSE).to eq('sse')
    end
  end

  describe '.build_subagents_config' do
    it 'builds config from snake_case keys' do
      config = described_class.build_subagents_config('enabled' => true, 'max_parallel' => 4)
      expect(config.enabled).to be(true)
      expect(config.max_parallel).to eq(4)
    end

    it 'builds config from camelCase keys' do
      config = described_class.build_subagents_config('enabled' => true, 'maxParallel' => 4)
      expect(config.max_parallel).to eq(4)
    end

    it 'defaults to zeros when keys missing' do
      config = described_class.build_subagents_config({})
      expect(config.enabled).to be(false)
      expect(config.max_parallel).to eq(0)
      expect(config.max_child_runs).to eq(0)
    end
  end

  describe '.build_default_capabilities_config' do
    subject(:config) { described_class.build_default_capabilities_config }

    it 'returns DeepForgeCapabilitiesConfig' do
      expect(config).to be_a(DeepForge::Contracts::DeepForgeCapabilitiesConfig)
    end

    it 'has all subsystems disabled' do
      expect(config.mcp.enabled).to be(false)
      expect(config.web.enabled).to be(false)
      expect(config.skills.enabled).to be(false)
      expect(config.subagents.enabled).to be(false)
      expect(config.attachments.enabled).to be(false)
      expect(config.memory.enabled).to be(false)
    end

    it 'sets default attachment limits' do
      expect(config.attachments.max_image_bytes).to eq(5 * 1024 * 1024)
      expect(config.attachments.max_image_dimension).to eq(4096)
    end
  end

  describe '.validate_mcp_server_config' do
    it 'requires command for stdio transport' do
      cfg = described_class::McpServerConfig.new(transport: 'stdio', command: nil, args: [],
                                                 trusted_workspace_roots: [])
      errors = described_class.validate_mcp_server_config(cfg)
      expect(errors).to include('stdio MCP servers require command')
    end

    it 'requires url for streamable-http' do
      cfg = described_class::McpServerConfig.new(transport: 'streamable-http', url: nil, trusted_workspace_roots: [])
      errors = described_class.validate_mcp_server_config(cfg)
      expect(errors.first).to include('require url')
    end

    it 'rejects non-http url scheme' do
      cfg = described_class::McpServerConfig.new(transport: 'streamable-http', url: 'ftp://example.com',
                                                 trusted_workspace_roots: [])
      errors = described_class.validate_mcp_server_config(cfg)
      expect(errors.first).to include('http or https')
    end

    it 'requires trusted workspace roots for workspace scope' do
      cfg = described_class::McpServerConfig.new(
        transport: 'stdio', command: 'node', trust_scope: 'workspace', trusted_workspace_roots: []
      )
      errors = described_class.validate_mcp_server_config(cfg)
      expect(errors.first).to include('trusted workspace root')
    end

    it 'returns empty array for valid config' do
      cfg = described_class::McpServerConfig.new(
        transport: 'stdio', command: 'node', args: [], trusted_workspace_roots: []
      )
      expect(described_class.validate_mcp_server_config(cfg)).to eq([])
    end
  end

  describe '.validate_mcp_search_config' do
    it 'returns error when topKDefault > topKMax' do
      cfg = described_class::McpSearchConfig.new(top_k_default: 10, top_k_max: 5, bm25: nil)
      errors = described_class.validate_mcp_search_config(cfg)
      expect(errors.first).to include('topKDefault')
    end

    it 'returns empty array when valid' do
      cfg = described_class::McpSearchConfig.new(top_k_default: 5, top_k_max: 10, bm25: nil)
      expect(described_class.validate_mcp_search_config(cfg)).to eq([])
    end
  end

  describe 'capability state computation helpers' do
    describe '.available_state' do
      it 'returns AVAILABLE state' do
        state = described_class.available_state
        expect(state.status).to eq('available')
        expect(state.enabled).to be(true)
        expect(state.available).to be(true)
      end
    end

    describe '.unavailable_state' do
      it 'returns UNAVAILABLE state with reason' do
        state = described_class.unavailable_state('not found')
        expect(state.status).to eq('unavailable')
        expect(state.reason).to eq('not found')
      end
    end

    describe '.provider_capability_state' do
      it 'returns DISABLED when not enabled' do
        state = described_class.provider_capability_state(false, 'off', true, 'n/a')
        expect(state.status).to eq('disabled')
      end

      it 'returns AVAILABLE when enabled and provider available' do
        state = described_class.provider_capability_state(true, 'off', true, 'n/a')
        expect(state.status).to eq('available')
      end

      it 'returns UNAVAILABLE when enabled but provider unavailable' do
        state = described_class.provider_capability_state(true, 'off', false, 'unreachable')
        expect(state.status).to eq('unavailable')
        expect(state.reason).to eq('unreachable')
      end
    end
  end
end
