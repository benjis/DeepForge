# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Node HTTP Server' do
  describe 'start_node_http_server' do
    it 'defines the start method' do
      expect(DeepForge::Server).to respond_to(:start_node_http_server)
    end
  end
end
