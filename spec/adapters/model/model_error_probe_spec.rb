# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/model/model_error_probe'

RSpec.describe DeepForge::Adapters::Model::ModelErrorProbe do
  describe '.deep_seek_host?' do
    it 'returns true for api.deepseek.com' do
      expect(described_class.deep_seek_host?('https://api.deepseek.com/v1')).to be true
    end

    it 'returns true for subdomain deepseek.com' do
      expect(described_class.deep_seek_host?('https://foo.deepseek.com/api')).to be true
    end

    it 'returns false for non-deepseek hosts' do
      expect(described_class.deep_seek_host?('https://api.openai.com/v1')).to be false
    end

    it 'returns false for invalid URIs' do
      expect(described_class.deep_seek_host?('not a url')).to be false
    end

    it 'is case-insensitive for host matching' do
      expect(described_class.deep_seek_host?('https://API.DEEPSEEK.COM/v1')).to be true
    end
  end

  describe '.probe_url' do
    it 'defaults to deepseek URL for empty input' do
      expect(described_class.probe_url('')).to eq('https://api.deepseek.com/v1/models')
    end

    it 'defaults to deepseek URL for invalid URI' do
      expect(described_class.probe_url('not a url')).to eq('https://api.deepseek.com/v1/models')
    end
  end

  describe '.probe_deep_seek_reachable' do
    before do
      allow(described_class).to receive(:probe_url).and_return('https://api.deepseek.com/v1/models')
    end

    it 'returns reachable true when probe gets < 500 status' do
      response = instance_double(Net::HTTPResponse, code: '200')
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = described_class.probe_deep_seek_reachable(base_url: 'https://api.deepseek.com')
      expect(result[:reachable]).to be true
      expect(result[:status]).to eq(200)
    end

    it 'returns reachable false when probe gets 500 status' do
      response = instance_double(Net::HTTPResponse, code: '500')
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = described_class.probe_deep_seek_reachable(base_url: 'https://api.deepseek.com')
      expect(result[:reachable]).to be false
    end

    it 'returns reachable false when probe raises an error' do
      allow(Net::HTTP).to receive(:get_response).and_raise(StandardError, 'connection refused')

      result = described_class.probe_deep_seek_reachable(base_url: 'https://api.deepseek.com')
      expect(result[:reachable]).to be false
      expect(result[:message]).to include('connection refused')
    end
  end
end
