# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/runtime_helpers'

RSpec.describe DeepForge::Server::RuntimeHelpers do
  describe '.create_immutable_prefix' do
    it 'returns a hash with system_prompt and pinned_constraints' do
      result = described_class.create_immutable_prefix(
        system_prompt: 'You are helpful.',
        pinned_constraints: %w[rule1 rule2]
      )
      expect(result).to eq({
                             system_prompt: 'You are helpful.',
                             pinned_constraints: %w[rule1 rule2]
                           })
    end
  end

  describe '.model_context_profiles_from_config' do
    it 'returns an empty hash' do
      expect(described_class.model_context_profiles_from_config).to eq({})
    end
  end

  describe '.model_capabilities_for_model' do
    it 'returns a hash with the model name' do
      result = described_class.model_capabilities_for_model('deepseek-chat', {})
      expect(result).to eq({ model: 'deepseek-chat' })
    end
  end

  describe '.build_mcp_tool_providers' do
    it 'returns default empty MCP providers' do
      result = described_class.build_mcp_tool_providers(nil)
      expect(result[:providers]).to eq([])
      expect(result[:connected_servers]).to eq(0)
      expect(result[:tool_count]).to eq(0)
    end
  end

  describe '.build_web_tool_providers' do
    it 'returns default empty web providers' do
      result = described_class.build_web_tool_providers(nil)
      expect(result[:providers]).to eq([])
      expect(result[:fetch_available]).to be false
      expect(result[:search_available]).to be false
    end
  end

  describe '.build_default_local_tools' do
    it 'returns an empty array' do
      expect(described_class.build_default_local_tools).to eq([])
    end
  end

  describe '.create_child_agent_executor' do
    it 'returns a proc' do
      executor = described_class.create_child_agent_executor
      expect(executor).to be_a(Proc)
    end
  end
end
