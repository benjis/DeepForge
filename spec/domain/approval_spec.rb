# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Domain do
  describe 'ApprovalStatus constants' do
    it 'defines PENDING, ALLOWED, DENIED, EXPIRED' do
      expect(DeepForge::Domain::ApprovalStatus::PENDING).to eq('pending')
      expect(DeepForge::Domain::ApprovalStatus::ALLOWED).to eq('allowed')
      expect(DeepForge::Domain::ApprovalStatus::DENIED).to eq('denied')
      expect(DeepForge::Domain::ApprovalStatus::EXPIRED).to eq('expired')
    end
  end

  describe 'ApprovalRequest struct' do
    it 'supports keyword init with all fields' do
      req = DeepForge::Domain::ApprovalRequest.new(
        id: 'a1', thread_id: 't1', turn_id: 'tr1',
        tool_name: 'bash', summary: 'run ls',
        status: 'pending', created_at: '2025-01-01T00:00:00Z'
      )
      expect(req.id).to eq('a1')
      expect(req.tool_name).to eq('bash')
    end
  end

  describe '.create_approval_request' do
    it 'creates a pending request with PENDING status' do
      req = described_class.create_approval_request(
        id: 'a1', thread_id: 't1', turn_id: 'tr1',
        tool_name: 'bash', summary: 'run command'
      )
      expect(req.status).to eq('pending')
      expect(req.id).to eq('a1')
      expect(req.thread_id).to eq('t1')
      expect(req.turn_id).to eq('tr1')
      expect(req.tool_name).to eq('bash')
      expect(req.summary).to eq('run command')
      expect(req.created_at).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
    end

    it 'uses provided created_at when given' do
      ts = '2025-06-01T12:00:00Z'
      req = described_class.create_approval_request(
        id: 'a1', thread_id: 't1', turn_id: 'tr1',
        tool_name: 'bash', summary: 'x', created_at: ts
      )
      expect(req.created_at).to eq(ts)
    end
  end

  describe '.resolve_approval_request' do
    let(:request) do
      described_class.create_approval_request(
        id: 'a1', thread_id: 't1', turn_id: 'tr1',
        tool_name: 'bash', summary: 'run'
      )
    end

    it 'returns a new request with ALLOWED status on allow' do
      resolved = described_class.resolve_approval_request(request, 'allow', reason: 'ok')
      expect(resolved.status).to eq('allowed')
      expect(resolved.reason).to eq('ok')
      expect(resolved.decided_at).to match(/\d{4}/)
    end

    it 'returns a new request with DENIED status on deny' do
      resolved = described_class.resolve_approval_request(request, 'deny')
      expect(resolved.status).to eq('denied')
    end

    it 'uses provided decided_at' do
      ts = '2025-06-01T12:00:00Z'
      resolved = described_class.resolve_approval_request(request, 'allow', decided_at: ts)
      expect(resolved.decided_at).to eq(ts)
    end

    it 'does not mutate the original request' do
      described_class.resolve_approval_request(request, 'allow')
      expect(request.status).to eq('pending')
    end
  end

  describe '.expire_approval_request' do
    let(:request) do
      described_class.create_approval_request(
        id: 'a1', thread_id: 't1', turn_id: 'tr1',
        tool_name: 'bash', summary: 'run'
      )
    end

    it 'returns a new request with EXPIRED status' do
      expired = described_class.expire_approval_request(request)
      expect(expired.status).to eq('expired')
      expect(expired.decided_at).to match(/\d{4}/)
    end

    it 'uses provided decided_at' do
      ts = '2025-06-01T12:00:00Z'
      expired = described_class.expire_approval_request(request, decided_at: ts)
      expect(expired.decided_at).to eq(ts)
    end

    it 'does not mutate the original' do
      described_class.expire_approval_request(request)
      expect(request.status).to eq('pending')
    end
  end
end
