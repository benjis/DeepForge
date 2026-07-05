# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe DeepForge::Config::DeepForgeConfig do
  describe '.expand_home_path' do
    it 'expands ~ to ::Dir.home' do
      expect(described_class.expand_home_path('~/test')).to eq(File.join(Dir.home, 'test'))
    end

    it 'expands bare ~' do
      expect(described_class.expand_home_path('~')).to eq(Dir.home)
    end

    it 'leaves absolute paths unchanged' do
      expect(described_class.expand_home_path('/tmp/test')).to eq('/tmp/test')
    end
  end

  describe '.config_path_for_data_dir' do
    it 'returns nil for nil/empty/whitespace input' do
      expect(described_class.config_path_for_data_dir(nil)).to be_nil
      expect(described_class.config_path_for_data_dir('')).to be_nil
      expect(described_class.config_path_for_data_dir('   ')).to be_nil
    end

    it 'joins data dir with config filename' do
      result = described_class.config_path_for_data_dir('/tmp/data')
      expect(result).to eq(File.join('/tmp/data', 'config.json'))
    end
  end

  describe '.validate_serve_config' do
    it 'extracts host and port' do
      config = described_class.validate_serve_config('host' => '0.0.0.0', 'port' => 8080)
      expect(config[:host]).to eq('0.0.0.0')
      expect(config[:port]).to eq(8080)
    end

    it 'uses default approval_policy and sandbox_mode' do
      config = described_class.validate_serve_config({})
      expect(config[:approval_policy]).to eq('suggest')
      expect(config[:sandbox_mode]).to eq('off')
    end

    it 'extracts data_dir, model, api_key, base_url' do
      config = described_class.validate_serve_config(
        'dataDir' => '/data', 'model' => 'gpt-4', 'apiKey' => 'sk-123', 'baseUrl' => 'https://api.example.com'
      )
      expect(config[:data_dir]).to eq('/data')
      expect(config[:model]).to eq('gpt-4')
      expect(config[:api_key]).to eq('sk-123')
      expect(config[:base_url]).to eq('https://api.example.com')
    end

    it 'extracts storage config with default backend' do
      config = described_class.validate_serve_config('storage' => { 'sqlitePath' => '/tmp/db.sqlite' })
      expect(config[:storage][:backend]).to eq('hybrid')
      expect(config[:storage][:sqlite_path]).to eq('/tmp/db.sqlite')
    end
  end

  describe '.validate_model_config' do
    it 'transforms model profiles' do
      config = described_class.validate_model_config(
        'profiles' => { 'gpt-4' => { 'contextWindowTokens' => 128_000, 'supportsToolCalling' => true } }
      )
      expect(config[:profiles]['gpt-4'][:context_window_tokens]).to eq(128_000)
      expect(config[:profiles]['gpt-4'][:supports_tool_calling]).to be(true)
    end
  end

  describe '.validate_context_compaction_config' do
    it 'validates summary_mode' do
      expect(described_class.validate_context_compaction_config('summaryMode' => 'heuristic')[:summary_mode]).to eq('heuristic')
    end

    it 'rejects invalid summary_mode' do
      expect(described_class.validate_context_compaction_config('summaryMode' => 'invalid')[:summary_mode]).to be_nil
    end
  end

  describe '.validate_config' do
    it 'builds full config from JSON' do
      json = {
        'serve' => { 'host' => '0.0.0.0', 'port' => 3000 },
        'models' => { 'profiles' => {} },
        'contextCompaction' => { 'summaryMode' => 'heuristic' },
        'runtime' => { 'toolStorm' => { 'enabled' => true } },
        'capabilities' => { 'skills' => true }
      }
      config = described_class.validate_config(json)
      expect(config[:serve][:host]).to eq('0.0.0.0')
      expect(config[:context_compaction][:summary_mode]).to eq('heuristic')
      expect(config[:capabilities]).to eq({ 'skills' => true })
    end

    it 'defaults capabilities to empty hash for empty JSON' do
      config = described_class.validate_config({})
      expect(config[:capabilities]).to eq({})
    end
  end

  describe '.read_config_file' do
    it 'reads and validates a valid config file' do
      file = Tempfile.new('config.json')
      file.write(JSON.generate('serve' => { 'host' => 'localhost' }))
      file.close
      result = described_class.read_config_file(file.path)
      expect(result).to be_a(described_class)
      expect(result.config[:serve][:host]).to eq('localhost')
      file.unlink
    end

    it 'raises on invalid JSON' do
      file = Tempfile.new('config.json')
      file.write('{invalid')
      file.close
      expect { described_class.read_config_file(file.path) }.to raise_error(RuntimeError, /Failed to parse/)
      file.unlink
    end

    it 'raises on missing file' do
      expect { described_class.read_config_file('/nonexistent.json') }.to raise_error(Errno::ENOENT)
    end
  end

  describe '.read_optional_config_file' do
    it 'returns nil for nil or nonexistent path' do
      expect(described_class.read_optional_config_file(nil)).to be_nil
      expect(described_class.read_optional_config_file('/nonexistent.json')).to be_nil
    end
  end

  describe '.validate_request_history_hygiene_config' do
    it 'extracts positive numeric values' do
      config = described_class.validate_request_history_hygiene_config(
        'maxToolResultLines' => 500, 'maxArrayItems' => 50
      )
      expect(config[:max_tool_result_lines]).to eq(500)
      expect(config[:max_array_items]).to eq(50)
    end

    it 'ignores zero and negative values' do
      config = described_class.validate_request_history_hygiene_config('maxToolResultLines' => 0, 'maxArrayItems' => -1)
      expect(config).to be_empty
    end
  end

  describe '.validate_token_economy_config' do
    it 'extracts boolean flags' do
      config = described_class.validate_token_economy_config('enabled' => true, 'conciseResponses' => true)
      expect(config[:enabled]).to be(true)
      expect(config[:concise_responses]).to be(true)
    end
  end
end
