# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::WorkspaceInspector do
  it 'raises NotImplementedError for status' do
    expect { subject.status(path: '.') }.to raise_error(NotImplementedError)
  end
end
