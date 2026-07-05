# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::App do
  it 'is a Roda subclass' do
    expect(described_class.ancestors).to include(Roda)
  end
end
