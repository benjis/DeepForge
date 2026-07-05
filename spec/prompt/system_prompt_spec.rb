# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/prompt/system_prompt'

RSpec.describe DeepForge::Prompt do
  describe 'DEEPFORGE_SYSTEM_PROMPT' do
    it 'is defined as a string' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to be_a(String)
    end

    it 'is not empty' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT.length).to be > 0
    end

    it 'identifies DeepForge' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('DeepForge')
    end

    it 'contains core identity section' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('Core identity')
    end

    it 'contains GUI contract section' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('GUI contract')
    end

    it 'contains coding behavior section' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('Coding behavior')
    end

    it 'contains tool behavior section' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('Tool behavior')
    end

    it 'contains cache behavior section' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('Cache behavior')
    end

    it 'contains response style section' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('Response style')
    end

    it 'contains safety and quality section' do
      expect(described_class::DEEPFORGE_SYSTEM_PROMPT).to include('Safety and quality')
    end
  end
end
