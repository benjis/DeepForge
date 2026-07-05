# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge::CLI serve' do
  it 'delegates to Server.start_deepforge_serve' do
    expect(DeepForge::CLI::SERVE_USAGE).to include('deepforge serve')
  end
end
