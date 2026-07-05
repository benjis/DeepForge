# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::WebProvider do
  it 'raises NotImplementedError for fetch' do
    expect { subject.fetch('http://example.com') }.to raise_error(NotImplementedError)
  end
end
