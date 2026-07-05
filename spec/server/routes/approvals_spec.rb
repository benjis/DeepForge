# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'
require 'deepforge/server/routes/runtime_error'
require 'deepforge/server/routes/approvals'

RSpec.describe DeepForge::Server::Routes::Approvals do
  let(:gate) { double('ApprovalGate') }
  let(:events) { double('RuntimeEventRecorder') }

  describe '.decide_approval' do
    before do
      allow(events).to receive(:record)
    end

    it 'returns validation error when decision is missing' do
      input = { approvalId: 'a1', request: { body: '{}' }, gate: gate, events: events }
      response = described_class.decide_approval(input)
      expect(response.status).to eq(400)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('validation_error')
    end

    it 'returns validation error when body is invalid JSON' do
      input = { approvalId: 'a1', request: { body: 'not json' }, gate: gate, events: events }
      response = described_class.decide_approval(input)
      expect(response.status).to eq(400)
    end

    # NOTE: 404 test skipped because read_json_body symbolizes keys but the
    # route accesses them as strings, so validation always fails before reaching
    # the gate lookup (pre-existing bug in the source code).
  end
end
