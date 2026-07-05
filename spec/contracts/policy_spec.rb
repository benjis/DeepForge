# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'ApprovalPolicy constants' do
    it 'defines all policies' do
      expect(described_class::ApprovalPolicy::ON_REQUEST).to eq('on-request')
      expect(described_class::ApprovalPolicy::UNTRUSTED).to eq('untrusted')
      expect(described_class::ApprovalPolicy::NEVER).to eq('never')
      expect(described_class::ApprovalPolicy::AUTO).to eq('auto')
      expect(described_class::ApprovalPolicy::SUGGEST).to eq('suggest')
    end
  end

  describe 'DEFAULT_APPROVAL_POLICY' do
    it 'is on-request' do
      expect(described_class::DEFAULT_APPROVAL_POLICY).to eq('on-request')
    end
  end

  describe 'SandboxMode constants' do
    it 'defines all modes' do
      expect(described_class::SandboxMode::READ_ONLY).to eq('read-only')
      expect(described_class::SandboxMode::WORKSPACE_WRITE).to eq('workspace-write')
      expect(described_class::SandboxMode::DANGER_FULL_ACCESS).to eq('danger-full-access')
      expect(described_class::SandboxMode::EXTERNAL_SANDBOX).to eq('external-sandbox')
    end
  end

  describe 'DEFAULT_SANDBOX_MODE' do
    it 'is workspace-write' do
      expect(described_class::DEFAULT_SANDBOX_MODE).to eq('workspace-write')
    end
  end
end
