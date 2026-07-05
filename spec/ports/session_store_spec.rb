# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::SessionStore do
  subject(:store) { described_class.new }

  it 'raises NotImplementedError on all methods' do
    expect { store.append_event('t1', nil) }.to raise_error(NotImplementedError)
    expect { store.append_item('t1', nil) }.to raise_error(NotImplementedError)
    expect { store.rewrite_items('t1', []) }.to raise_error(NotImplementedError)
    expect { store.update_item('t1', 'i1', {}) }.to raise_error(NotImplementedError)
    expect { store.load_events_since('t1', 0) }.to raise_error(NotImplementedError)
    expect { store.load_items('t1') }.to raise_error(NotImplementedError)
    expect { store.load_session('t1') }.to raise_error(NotImplementedError)
    expect { store.upsert_session(nil) }.to raise_error(NotImplementedError)
    expect { store.highest_seq('t1') }.to raise_error(NotImplementedError)
    expect { store.reset_memory }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::AgentThreadStore do
  subject(:store) { described_class.new }

  it 'raises NotImplementedError on all methods' do
    expect { store.list }.to raise_error(NotImplementedError)
    expect { store.get('t1') }.to raise_error(NotImplementedError)
    expect { store.upsert(nil) }.to raise_error(NotImplementedError)
    expect { store.delete('t1') }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::ToolHost do
  subject(:host) { described_class.new(id: 'host1') }

  it 'exposes id' do
    expect(host.id).to eq('host1')
  end

  it 'raises NotImplementedError on #list_tools' do
    expect { host.list_tools }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError on #execute' do
    expect { host.execute(nil, nil) }.to raise_error(NotImplementedError)
  end

  it 'does not raise on #clear_read_tracker' do
    expect { host.clear_read_tracker }.not_to raise_error
  end
end

RSpec.describe DeepForge::Ports::UserInputGate do
  subject(:gate) { described_class.new }

  it 'raises NotImplementedError on all methods' do
    expect { gate.request(nil) }.to raise_error(NotImplementedError)
    expect { gate.get('u1') }.to raise_error(NotImplementedError)
    expect { gate.resolve('u1', {}) }.to raise_error(NotImplementedError)
    expect { gate.pending }.to raise_error(NotImplementedError)
    expect { gate.reset }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::WebProvider do
  subject(:provider) { described_class.new }

  it 'raises NotImplementedError on all methods' do
    expect { provider.id }.to raise_error(NotImplementedError)
    expect { provider.fetch(nil) }.to raise_error(NotImplementedError)
    expect { provider.search(nil) }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::WorkspaceInspector do
  subject(:inspector) { described_class.new }

  it 'raises NotImplementedError on #status' do
    expect { inspector.status('/tmp') }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::UnavailableWebProvider do
  subject(:provider) { described_class.new(id: 'unavail') }

  it 'exposes id' do
    expect(provider.id).to eq('unavail')
  end

  it 'raises NotImplementedError on fetch' do
    expect { provider.fetch(nil) }.to raise_error(NotImplementedError, /unavailable/)
  end

  it 'raises NotImplementedError on search' do
    expect { provider.search(nil) }.to raise_error(NotImplementedError, /unavailable/)
  end
end

RSpec.describe DeepForge::Ports::DeterministicWebProvider do
  subject(:provider) { described_class.new(id: 'det', pages: pages, search_results: search_results) }

  let(:pages) do
    {
      'https://example.com' => {
        url: 'https://example.com', final_url: 'https://example.com',
        title: 'Example', content_type: 'text/html', text: 'Hello'
      }
    }
  end
  let(:search_results) do
    {
      'ruby' => [
        { url: 'https://ruby-lang.org', title: 'Ruby', snippet: 'A programming language' }
      ]
    }
  end

  describe '#fetch' do
    it 'returns a WebFetchResult for known URL' do
      req = DeepForge::Ports::WebFetchRequest.new(url: 'https://example.com', max_bytes: 1024, timeout_ms: 5000)
      result = provider.fetch(req)
      expect(result).to be_a(DeepForge::Ports::WebFetchResult)
      expect(result.text).to eq('Hello')
      expect(result.truncated).to be(false)
    end

    it 'raises for unknown URL' do
      req = DeepForge::Ports::WebFetchRequest.new(url: 'https://unknown.com', max_bytes: 1024, timeout_ms: 5000)
      expect { provider.fetch(req) }.to raise_error(ArgumentError, /not found/)
    end

    it 'raises when content exceeds max_bytes' do
      req = DeepForge::Ports::WebFetchRequest.new(url: 'https://example.com', max_bytes: 2, timeout_ms: 5000)
      expect { provider.fetch(req) }.to raise_error(ArgumentError, /byte limit/)
    end
  end

  describe '#search' do
    it 'returns WebSearchResult array for known query' do
      req = DeepForge::Ports::WebSearchRequest.new(query: 'ruby', limit: 5, timeout_ms: 5000)
      results = provider.search(req)
      expect(results.size).to eq(1)
      expect(results.first).to be_a(DeepForge::Ports::WebSearchResult)
      expect(results.first.url).to eq('https://ruby-lang.org')
      expect(results.first.rank).to eq(1)
      expect(results.first.provider).to eq('det')
    end

    it 'returns empty array for unknown query' do
      req = DeepForge::Ports::WebSearchRequest.new(query: 'unknown', limit: 5, timeout_ms: 5000)
      expect(provider.search(req)).to eq([])
    end

    it 'respects limit' do
      req = DeepForge::Ports::WebSearchRequest.new(query: 'ruby', limit: 0, timeout_ms: 5000)
      expect(provider.search(req)).to eq([])
    end
  end
end

RSpec.describe DeepForge::Ports do
  describe '.source_id_for' do
    it 'returns a deterministic string starting with web_' do
      id1 = described_class.source_id_for('fetch', 'https://example.com')
      id2 = described_class.source_id_for('fetch', 'https://example.com')
      expect(id1).to start_with('web_fetch_')
      expect(id1).to eq(id2)
    end

    it 'returns different IDs for different inputs' do
      id1 = described_class.source_id_for('fetch', 'a')
      id2 = described_class.source_id_for('fetch', 'b')
      expect(id1).not_to eq(id2)
    end

    it 'handles search kind' do
      id = described_class.source_id_for('search', 'query')
      expect(id).to start_with('web_search_')
    end
  end
end
