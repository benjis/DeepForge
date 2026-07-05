# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'
require 'deepforge/server/routes/runtime_error'
require 'deepforge/server/routes/turns'

RSpec.describe DeepForge::Server::Routes::Turns do
  let(:turn_service) { double('TurnService') }

  describe '.start_turn' do
    it 'starts a turn with valid prompt' do
      result = { thread_id: 't1', turn_id: 'turn1', status: 'running' }
      allow(turn_service).to receive(:start_turn).and_return(result)

      request = { body: '{"prompt":"hello"}' }
      response = described_class.start_turn(turn_service, 't1', request)

      expect(response.status).to eq(202)
      body = JSON.parse(response.body)
      expect(body['thread_id']).to eq('t1')
      expect(body['turn_id']).to eq('turn1')
    end

    it 'calls on_started callback when provided' do
      result = { thread_id: 't1', turn_id: 'turn1', status: 'running' }
      allow(turn_service).to receive(:start_turn).and_return(result)

      callback_called = false
      request = { body: '{"prompt":"hello"}' }
      described_class.start_turn(turn_service, 't1', request, on_started: ->(_r) { callback_called = true })

      expect(callback_called).to be true
    end

    it 'returns validation error when prompt is missing' do
      request = { body: '{"model":"m1"}' }
      response = described_class.start_turn(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end

    it 'returns validation error for invalid JSON' do
      request = { body: 'not json' }
      response = described_class.start_turn(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end
  end

  describe '.get_turn' do
    it 'returns the turn when found' do
      turn = { id: 'turn1', status: 'running' }
      allow(turn_service).to receive(:get_turn).with('t1', 'turn1').and_return(turn)

      response = described_class.get_turn(turn_service, 't1', 'turn1')
      body = JSON.parse(response.body)
      expect(body['id']).to eq('turn1')
    end

    it 'returns 404 when turn not found' do
      allow(turn_service).to receive(:get_turn).with('t1', 'missing').and_return(nil)

      response = described_class.get_turn(turn_service, 't1', 'missing')
      expect(response.status).to eq(404)
    end
  end

  describe '.interrupt_turn' do
    it 'interrupts the turn' do
      allow(turn_service).to receive(:interrupt_turn).and_return({ status: 'aborted' })

      request = { body: '{}' }
      response = described_class.interrupt_turn(turn_service, 't1', 'turn1', request)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('aborted')
      expect(body['turnId']).to eq('turn1')
    end
  end

  describe '.compact_turn' do
    it 'compacts the turn' do
      allow(turn_service).to receive(:compact).and_return({ compacted: true })

      request = { body: '{}' }
      response = described_class.compact_turn(turn_service, 't1', request)
      body = JSON.parse(response.body)
      expect(body['compacted']).to be true
    end

    it 'validates strategy parameter' do
      request = { body: '{"strategy":"invalid"}' }
      response = described_class.compact_turn(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end

    it 'allows valid strategies' do
      allow(turn_service).to receive(:compact).and_return({ compacted: true })

      %w[full targeted recent summary].each do |strategy|
        request = { body: "{\"strategy\":\"#{strategy}\"}" }
        response = described_class.compact_turn(turn_service, 't1', request)
        expect(response.status).not_to eq(400)
      end
    end
  end
end
