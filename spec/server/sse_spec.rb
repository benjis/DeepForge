# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/middleware/sse'

RSpec.describe DeepForge::Server do
  describe '.encode_sse_event' do
    it 'encodes an event into SSE format' do
      event = { seq: 1, kind: 'heartbeat', timestamp: '2024-01-01T00:00:00Z' }
      result = described_class.encode_sse_event(event)

      expect(result).to include('id: 1')
      expect(result).to include('event: heartbeat')
      expect(result).to include('data: ')
      expect(result).to end_with("\n\n")
    end

    it 'serializes the full event as JSON in the data field' do
      event = { seq: 42, kind: 'text', text: 'hello' }
      result = described_class.encode_sse_event(event)

      data_line = result.lines.find { |l| l.start_with?('data: ') }
      data_json = data_line.strip.sub('data: ', '')
      parsed = JSON.parse(data_json)
      expect(parsed['seq']).to eq(42)
      expect(parsed['kind']).to eq('text')
      expect(parsed['text']).to eq('hello')
    end

    it 'handles events with special characters' do
      event = { seq: 1, kind: 'error', message: 'line1\nline2' }
      result = described_class.encode_sse_event(event)
      expect(result).to include('event: error')
    end
  end
end
