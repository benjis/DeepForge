# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::Clock do
  it 'raises NotImplementedError for now' do
    expect { subject.now }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for now_iso' do
    expect { subject.now_iso }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for now_ms' do
    expect { subject.now_ms }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::SystemClock do
  subject(:clock) { described_class.new }

  it 'returns a Time object from now' do
    expect(clock.now).to be_a(Time)
  end

  it 'returns an ISO 8601 string from now_iso' do
    result = clock.now_iso
    expect(result).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
  end

  it 'returns milliseconds from now_ms' do
    result = clock.now_ms
    expect(result).to be_a(Integer)
    expect(result).to be > 0
  end
end
