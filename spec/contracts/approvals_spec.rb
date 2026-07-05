# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'ApprovalDecisionRequest' do
    it 'creates with keyword init' do
      req = described_class::ApprovalDecisionRequest.new(decision: 'allow', reason: 'ok')
      expect(req.decision).to eq('allow')
      expect(req.reason).to eq('ok')
    end

    it 'defaults reason to nil' do
      req = described_class::ApprovalDecisionRequest.new(decision: 'deny')
      expect(req.reason).to be_nil
    end
  end

  describe 'ApprovalDecisionResponse' do
    it 'creates with all fields' do
      resp = described_class::ApprovalDecisionResponse.new(approval_id: 'a1', decision: 'allow', status: 'allowed')
      expect(resp.approval_id).to eq('a1')
      expect(resp.status).to eq('allowed')
    end
  end
end
