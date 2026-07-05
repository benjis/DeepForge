# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Config do
  it 'defines DEFAULT_DEEPFORGE_MODEL' do
    expect(DeepForge::Config::DEFAULT_DEEPFORGE_MODEL).to be_a(String)
    expect(DeepForge::Config::DEFAULT_DEEPFORGE_MODEL).not_to be_empty
  end
end
