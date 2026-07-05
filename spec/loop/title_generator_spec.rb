# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/title_generator'

RSpec.describe DeepForge::Loop::TitleGenerator do
  describe '.sanitize_title' do
    it 'strips title prefix' do
      expect(described_class.sanitize_title('Title: My Chat')).to eq('My Chat')
    end

    it 'strips Title: with Chinese colon' do
      expect(described_class.sanitize_title('Title：My Chat')).to eq('My Chat')
    end

    it 'removes surrounding quotes' do
      expect(described_class.sanitize_title('"My Chat"')).to eq('My Chat')
    end

    it 'removes markdown heading' do
      expect(described_class.sanitize_title('# My Chat')).to eq('My Chat')
    end

    it 'removes surrounding asterisks' do
      expect(described_class.sanitize_title('*My Chat*')).to eq('My Chat')
    end

    it 'truncates to MAX_TITLE_CHARS' do
      long_title = 'a' * 100
      result = described_class.sanitize_title(long_title)
      expect(result.length).to be <= described_class::MAX_TITLE_CHARS
    end

    it 'returns nil for empty title' do
      expect(described_class.sanitize_title('')).to be_nil
    end

    it 'returns nil for whitespace-only title' do
      expect(described_class.sanitize_title('   ')).to be_nil
    end

    it 'strips newlines and takes first non-empty line' do
      expect(described_class.sanitize_title("ignored\nActual Title")).to eq('ignored')
    end

    it 'normalizes internal whitespace' do
      expect(described_class.sanitize_title('My   Chat   Here')).to eq('My Chat Here')
    end

    it 'handles various quote styles' do
      # The regex in sanitize_title only matches ASCII quotes and corner brackets
      expect(described_class.sanitize_title('「My Chat」')).to eq('My Chat')
    end
  end

  describe '.resolve_role_model' do
    it 'uses role model when provided' do
      result = described_class.resolve_role_model(role_model: 'my-model')
      expect(result[:model]).to eq('my-model')
    end

    it 'uses role provider_id when provided' do
      result = described_class.resolve_role_model(
        role_model: 'my-model',
        role_provider_id: 'my-provider'
      )
      expect(result[:provider_id]).to eq('my-provider')
    end

    it 'strips whitespace from model' do
      result = described_class.resolve_role_model(role_model: '  my-model  ')
      expect(result[:model]).to eq('my-model')
    end
  end

  describe '.generate_thread_title' do
    let(:model_client) { double('model_client') }
    let(:signal) { double('signal', aborted?: false) }

    before do
      unless Concurrent::Promises.respond_to?(:reschedule_event)
        Concurrent::Promises.define_singleton_method(:reschedule_event) do |*_args, &blk|
          blk&.call
          Object.new.tap { |o| def o.cancel; end }
        end
      end
    end

    it 'returns nil when user_text is empty' do
      result = described_class.generate_thread_title(
        thread_id: 't1', turn_id: 'r1',
        model_client: model_client, model: 'test',
        user_text: ''
      )
      expect(result).to be_nil
    end

    it 'returns nil when signal is aborted' do
      aborted_signal = double('signal', aborted?: true)
      result = described_class.generate_thread_title(
        thread_id: 't1', turn_id: 'r1',
        model_client: model_client, model: 'test',
        user_text: 'hello',
        abort_signal: aborted_signal
      )
      expect(result).to be_nil
    end

    it 'returns sanitized title from model response' do
      allow(model_client).to receive(:stream).and_return([{ kind: 'assistant_text_delta', text: 'My Chat Title' }])

      result = described_class.generate_thread_title(
        thread_id: 't1', turn_id: 'r1',
        model_client: model_client, model: 'test',
        user_text: 'hello world'
      )
      expect(result).to eq('My Chat Title')
    end

    it 'returns nil on error' do
      allow(model_client).to receive(:stream).and_return([{ kind: 'error', message: 'failed' }])

      result = described_class.generate_thread_title(
        thread_id: 't1', turn_id: 'r1',
        model_client: model_client, model: 'test',
        user_text: 'hello'
      )
      expect(result).to be_nil
    end

    it 'returns nil on exception' do
      allow(model_client).to receive(:stream).and_raise('boom')

      result = described_class.generate_thread_title(
        thread_id: 't1', turn_id: 'r1',
        model_client: model_client, model: 'test',
        user_text: 'hello'
      )
      expect(result).to be_nil
    end

    it 'returns nil when response is empty after sanitization' do
      allow(model_client).to receive(:stream).and_return([{ kind: 'assistant_text_delta', text: '   ' }])

      result = described_class.generate_thread_title(
        thread_id: 't1', turn_id: 'r1',
        model_client: model_client, model: 'test',
        user_text: 'hello'
      )
      expect(result).to be_nil
    end
  end

  describe '::TITLE_SYSTEM_PROMPT' do
    it 'is a non-empty string' do
      expect(described_class::TITLE_SYSTEM_PROMPT).to be_a(String)
      expect(described_class::TITLE_SYSTEM_PROMPT).not_to be_empty
    end
  end

  describe '::MAX_TITLE_CHARS' do
    it 'is 50' do
      expect(described_class::MAX_TITLE_CHARS).to eq(50)
    end
  end
end
