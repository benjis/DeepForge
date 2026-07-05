# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/middleware/sse'
require 'deepforge/server/routes/events'

RSpec.describe DeepForge::Server::Routes do
  describe '.build_event_stream_response' do
    it 'returns an SSE response structure' do
      session_store = double('SessionStore')
      event_bus = double('SessionStore')
      allow(session_store).to receive(:load_events_since).and_return([])
      allow(event_bus).to receive(:subscribe).and_return(-> {})

      input = {
        request: { url: 'http://localhost/v1/threads/t1/events', headers: {} },
        thread_id: 't1',
        session_store: session_store,
        event_bus: event_bus,
        allocate_seq: ->(_tid) { 1 }
      }

      response = described_class.build_event_stream_response(input)
      expect(response[:status]).to eq(200)
      expect(response[:headers]['content-type']).to include('text/event-stream')
      expect(response[:body]).to be_a(Proc)
    end
  end
end
