# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::ApprovalGate do
  subject(:gate) { described_class.new }

  it 'raises NotImplementedError on #request' do
    expect { gate.request(nil) }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError on #decide' do
    expect { gate.decide('a1', 'allow') }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError on #pending' do
    expect { gate.pending }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError on #get' do
    expect { gate.get('a1') }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::Clock do
  subject(:clock) { described_class.new }

  it 'raises NotImplementedError on #now' do
    expect { clock.now }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError on #now_iso' do
    expect { clock.now_iso }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError on #now_ms' do
    expect { clock.now_ms }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::SystemClock do
  subject(:clock) { described_class.new }

  it 'returns a Time object from #now' do
    expect(clock.now).to be_a(Time)
  end

  it 'returns ISO 8601 string from #now_iso' do
    result = clock.now_iso
    expect(result).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
  end

  it 'returns integer milliseconds from #now_ms' do
    expect(clock.now_ms).to be_a(Integer)
    expect(clock.now_ms).to be > 0
  end
end

RSpec.describe DeepForge::Ports::EventBus do
  subject(:bus) { described_class.new }

  it 'raises NotImplementedError on all methods' do
    expect { bus.publish(nil) }.to raise_error(NotImplementedError)
    expect { bus.subscribe('t1', nil) }.to raise_error(NotImplementedError)
    expect { bus.snapshot_since('t1', 0) }.to raise_error(NotImplementedError)
    expect { bus.highest_seq('t1') }.to raise_error(NotImplementedError)
    expect { bus.reset }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::IdGenerator do
  it 'raises NotImplementedError on #next' do
    gen = described_class.new
    expect { gen.next('prefix') }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Adapters::RandomIdGenerator do
  subject(:gen) { described_class.new }

  it 'generates IDs with the given prefix' do
    id = gen.next('turn')
    expect(id).to start_with('turn_')
  end

  it 'generates unique IDs on successive calls' do
    ids = Array.new(10) { gen.next('id') }
    expect(ids.uniq.size).to eq(10)
  end
end

RSpec.describe DeepForge::Ports::SequentialIdGenerator do
  subject(:gen) { described_class.new }

  it 'generates sequential IDs starting from 1' do
    expect(gen.next('item')).to eq('item_1')
    expect(gen.next('item')).to eq('item_2')
    expect(gen.next('turn')).to eq('turn_3')
  end
end
