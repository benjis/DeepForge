# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/web_tool_provider'

RSpec.describe DeepForge::Adapters::Tool::WebToolProvider do
  describe 'constants' do
    it 'defines DEFAULT_WEB_TIMEOUT_MS' do
      expect(described_class::DEFAULT_WEB_TIMEOUT_MS).to eq(15_000)
    end

    it 'defines DEFAULT_WEB_MAX_BYTES' do
      expect(described_class::DEFAULT_WEB_MAX_BYTES).to eq(1_000_000)
    end

    it 'defines DEFAULT_SEARCH_LIMIT' do
      expect(described_class::DEFAULT_SEARCH_LIMIT).to eq(5)
    end

    it 'defines MAX_SEARCH_LIMIT' do
      expect(described_class::MAX_SEARCH_LIMIT).to eq(10)
    end
  end

  describe '.build' do
    it 'returns empty result when config disabled' do
      config = { enabled: false }
      result = described_class.build(config, described_class::WebToolProviderOptions.new)
      expect(result.providers).to be_empty
      expect(result.fetch_available).to be false
      expect(result.search_available).to be false
    end

    it 'returns empty result when config nil' do
      result = described_class.build(nil)
      expect(result.providers).to be_empty
    end

    it 'creates fetch tool when enabled' do
      config = { enabled: true, fetch_enabled: true, search_enabled: false }
      result = described_class.build(config, described_class::WebToolProviderOptions.new)
      expect(result.providers.length).to eq(1)
      tool_names = result.providers.first[:tools].map { |t| t[:name] }
      expect(tool_names).to include('web_fetch')
    end

    it 'creates search tool when enabled' do
      config = { enabled: true, fetch_enabled: false, search_enabled: true }
      result = described_class.build(config, described_class::WebToolProviderOptions.new)
      expect(result.providers.length).to eq(1)
      tool_names = result.providers.first[:tools].map { |t| t[:name] }
      expect(tool_names).to include('web_search')
    end

    it 'creates both tools when both enabled' do
      config = { enabled: true, fetch_enabled: true, search_enabled: true }
      result = described_class.build(config, described_class::WebToolProviderOptions.new)
      tool_names = result.providers.first[:tools].map { |t| t[:name] }
      expect(tool_names).to include('web_fetch', 'web_search')
    end
  end

  describe '.validate_url_policy' do
    let(:config) { { enabled: true, deny_domains: [], allow_domains: [] } }

    it 'allows valid http URL' do
      result = described_class.validate_url_policy('http://example.com', config)
      expect(result[:ok]).to be true
    end

    it 'allows valid https URL' do
      result = described_class.validate_url_policy('https://example.com', config)
      expect(result[:ok]).to be true
    end

    it 'rejects ftp URL' do
      result = described_class.validate_url_policy('ftp://example.com', config)
      expect(result[:ok]).to be false
      expect(result[:reason]).to include('http and https')
    end

    it 'rejects invalid URL' do
      result = described_class.validate_url_policy('not a url', config)
      expect(result[:ok]).to be false
    end

    it 'rejects denied domains' do
      config = { enabled: true, deny_domains: ['blocked.com'], allow_domains: [] }
      result = described_class.validate_url_policy('https://blocked.com/page', config)
      expect(result[:ok]).to be false
      expect(result[:reason]).to include('denied')
    end

    it 'rejects non-allowed domains when allow list exists' do
      config = { enabled: true, deny_domains: [], allow_domains: ['allowed.com'] }
      result = described_class.validate_url_policy('https://other.com/page', config)
      expect(result[:ok]).to be false
      expect(result[:reason]).to include('not allowed')
    end

    it 'allows subdomains of allowed domains' do
      config = { enabled: true, deny_domains: [], allow_domains: ['example.com'] }
      result = described_class.validate_url_policy('https://sub.example.com/page', config)
      expect(result[:ok]).to be true
    end
  end

  describe '.domain_matches?' do
    it 'matches exact domain' do
      expect(described_class.domain_matches?('example.com', 'example.com')).to be true
    end

    it 'matches subdomain' do
      expect(described_class.domain_matches?('sub.example.com', 'example.com')).to be true
    end

    it 'does not match different domain' do
      expect(described_class.domain_matches?('other.com', 'example.com')).to be false
    end

    it 'handles leading dot in domain' do
      expect(described_class.domain_matches?('example.com', '.example.com')).to be true
    end
  end

  describe '.pick_string' do
    it 'returns stripped string' do
      expect(described_class.pick_string(' hello ')).to eq('hello')
    end

    it 'returns nil for non-string' do
      expect(described_class.pick_string(123)).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.pick_string('')).to be_nil
      expect(described_class.pick_string('  ')).to be_nil
    end
  end

  describe '.bounded_int' do
    it 'returns value within bounds' do
      expect(described_class.bounded_int(5, 10, 1, 20)).to eq(5)
    end

    it 'clamps to min' do
      expect(described_class.bounded_int(0, 10, 1, 20)).to eq(1)
    end

    it 'clamps to max' do
      expect(described_class.bounded_int(100, 10, 1, 20)).to eq(20)
    end

    it 'returns fallback for non-numeric' do
      expect(described_class.bounded_int('bad', 10, 1, 20)).to eq(10)
    end

    it 'returns fallback for nil' do
      expect(described_class.bounded_int(nil, 10, 1, 20)).to eq(10)
    end
  end

  describe '.extract_readable_text' do
    it 'extracts text from plain text' do
      result = described_class.extract_readable_text('hello world', 'text/plain')
      expect(result[:text]).to eq('hello world')
    end

    it 'extracts text and title from HTML' do
      html = '<html><head><title>Test Page</title></head><body><p>Hello World</p></body></html>'
      result = described_class.extract_readable_text(html, 'text/html')
      expect(result[:text]).to include('Hello World')
      expect(result[:title]).to eq('Test Page')
    end

    it 'strips script tags from HTML' do
      html = '<html><body><script>alert("xss")</script><p>Content</p></body></html>'
      result = described_class.extract_readable_text(html, 'text/html')
      expect(result[:text]).not_to include('alert')
      expect(result[:text]).to include('Content')
    end

    it 'strips style tags from HTML' do
      html = '<html><body><style>.x{color:red}</style><p>Content</p></body></html>'
      result = described_class.extract_readable_text(html, 'text/html')
      expect(result[:text]).not_to include('color:red')
    end
  end

  describe '.decode_html_entities' do
    it 'decodes common entities' do
      expect(described_class.decode_html_entities('&amp;')).to eq('&')
      expect(described_class.decode_html_entities('&lt;')).to eq('<')
      expect(described_class.decode_html_entities('&gt;')).to eq('>')
      expect(described_class.decode_html_entities('&quot;')).to eq('"')
      expect(described_class.decode_html_entities('&#39;')).to eq("'")
      expect(described_class.decode_html_entities('&nbsp;')).to eq(' ')
    end
  end

  describe '.normalize_whitespace' do
    it 'normalizes spaces and newlines' do
      result = described_class.normalize_whitespace("hello   world\n\n\n\nend")
      expect(result).to eq("hello world\n\nend")
    end

    it 'strips leading and trailing whitespace' do
      result = described_class.normalize_whitespace('  hello  ')
      expect(result).to eq('hello')
    end

    it 'removes carriage returns' do
      result = described_class.normalize_whitespace("hello\r\nworld")
      expect(result).to eq("hello\nworld")
    end
  end

  describe '.telemetry' do
    it 'generates telemetry hash' do
      result = described_class.telemetry(
        started_at: (Time.now.to_i * 1000) - 100,
        policy: 'allowed',
        url: 'https://example.com'
      )
      expect(result[:policy]).to eq('allowed')
      expect(result[:url]).to eq('https://example.com')
      expect(result[:duration_ms]).to be >= 0
      expect(result[:cache_status]).to eq('miss')
    end
  end

  describe '.tool_error' do
    it 'returns error hash' do
      result = described_class.tool_error('code', 'message')
      expect(result[:output][:error][:code]).to eq('code')
      expect(result[:output][:error][:message]).to eq('message')
      expect(result[:is_error]).to be true
    end

    it 'includes telemetry when provided' do
      telemetry = { provider: 'test' }
      result = described_class.tool_error('code', 'message', telemetry)
      expect(result[:output][:telemetry]).to eq(telemetry)
    end
  end

  describe '.fetch_output' do
    it 'formats fetch result' do
      result_hash = {
        source_id: 's1', url: 'http://example.com', final_url: 'http://example.com',
        title: 'Test', retrieved_at: '2024-01-01T00:00:00Z', content_type: 'text/html',
        text: 'hello', byte_count: 5, truncated: false
      }
      output = described_class.fetch_output(result_hash, {})
      expect(output[:source_id]).to eq('s1')
      expect(output[:text]).to eq('hello')
      expect(output[:sources].length).to eq(1)
      expect(output[:citations].length).to eq(1)
    end
  end

  describe '.search_output' do
    it 'formats search results' do
      results = [{ source_id: 's1', url: 'http://example.com', title: 'Test' }]
      output = described_class.search_output('query', 'provider', results, {})
      expect(output[:query]).to eq('query')
      expect(output[:provider]).to eq('provider')
      expect(output[:results].length).to eq(1)
      expect(output[:sources].length).to eq(1)
    end
  end

  describe 'FetchWebProvider' do
    it 'has fetch method' do
      provider = described_class::FetchWebProvider.new
      expect(provider.id).to eq('fetch')
      expect(provider).to respond_to(:fetch)
    end
  end

  describe 'UnavailableWebProvider' do
    it 'has id' do
      provider = described_class::UnavailableWebProvider.new('test')
      expect(provider.id).to eq('test')
    end

    it 'defaults id to unavailable' do
      provider = described_class::UnavailableWebProvider.new
      expect(provider.id).to eq('unavailable')
    end
  end
end
