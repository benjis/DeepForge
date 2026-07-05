# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge::CLI agent_cli' do
  it 'defines AGENT_CLI_USAGE constant' do
    expect(DeepForge::CLI::AGENT_CLI_USAGE).to include('deepforge')
  end
end
