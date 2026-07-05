# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::IdGenerator do
  it 'raises NotImplementedError for next' do
    expect { subject.next('prefix') }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::RandomIdGenerator do
  subject(:generator) do
    described_class.new(random: lambda {
      counter[0] += 1
      counter[0].to_f / 10
    })
  end

  let(:counter) { [-1] }

  it 'generates an ID with the given prefix' do
    result = generator.next('thr')
    expect(result).to start_with('thr_')
  end

  it 'generates unique IDs on successive calls' do
    ids = Array.new(10) { generator.next('id') }
    expect(ids.uniq.size).to eq(10)
  end
end

RSpec.describe DeepForge::Ports::SequentialIdGenerator do
  subject(:generator) { described_class.new }

  it 'generates sequential IDs' do
    expect(generator.next('thr')).to eq('thr_1')
    expect(generator.next('thr')).to eq('thr_2')
    expect(generator.next('thr')).to eq('thr_3')
  end

  it 'tracks sequence independently per prefix' do
    expect(generator.next('a')).to eq('a_1')
    expect(generator.next('b')).to eq('b_2')
    expect(generator.next('a')).to eq('a_3')
  end
end
