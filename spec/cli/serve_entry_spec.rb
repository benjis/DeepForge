# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge::CLI serve_entry' do
  it 'defines DEEPFORGE_READY_PREFIX' do
    expect(DeepForge::CLI::DEEPFORGE_READY_PREFIX).to eq('DEEPFORGE_READY ')
  end
end
