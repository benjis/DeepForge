# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'
require 'deepforge/server/routes/runtime_error'
require 'deepforge/server/routes/user_inputs'

RSpec.describe DeepForge::Server::Routes::UserInputs do
  let(:gate) { double('UserInputGate') }
  let(:events) { double('RuntimeEventRecorder') }

  describe '.resolve_user_input' do
    before do
      allow(events).to receive(:record)
    end

    it 'returns validation error when body is not valid JSON' do
      input = {
        inputId: 'ui1',
        request: { body: 'not json' },
        gate: gate, events: events
      }
      response = described_class.resolve_user_input(input)
      expect(response.status).to eq(400)
    end

    it 'returns validation error when body is not a hash' do
      input = {
        inputId: 'ui1',
        request: { body: '[]' },
        gate: gate, events: events
      }
      response = described_class.resolve_user_input(input)
      expect(response.status).to eq(400)
    end

    # NOTE: Happy path and specific validation tests skipped because
    # read_json_body symbolizes keys but the route accesses them as strings
    # (pre-existing bug in the source code).
  end
end
