# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/review/review_prompt'

RSpec.describe DeepForge::Review do
  describe 'DEEPFORGE_REVIEW_PROMPT' do
    it 'is defined as a string' do
      expect(described_class::DEEPFORGE_REVIEW_PROMPT).to be_a(String)
    end

    it 'contains JSON shape instructions' do
      expect(described_class::DEEPFORGE_REVIEW_PROMPT).to include('findings')
      expect(described_class::DEEPFORGE_REVIEW_PROMPT).to include('overallCorrectness')
      expect(described_class::DEEPFORGE_REVIEW_PROMPT).to include('overallConfidenceScore')
    end

    it 'mentions priority levels' do
      expect(described_class::DEEPFORGE_REVIEW_PROMPT).to include('P0')
      expect(described_class::DEEPFORGE_REVIEW_PROMPT).to include('P3')
    end

    it 'instructs to return JSON only' do
      expect(described_class::DEEPFORGE_REVIEW_PROMPT).to include('Return JSON only')
    end
  end
end
