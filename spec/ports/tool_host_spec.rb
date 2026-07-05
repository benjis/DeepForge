# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::ToolHost do
  subject(:host) { described_class.new(id: 'test-host') }

  it 'raises NotImplementedError for list_tools' do
    expect { host.list_tools }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for execute' do
    expect { host.execute(nil, nil) }.to raise_error(NotImplementedError)
  end
end
