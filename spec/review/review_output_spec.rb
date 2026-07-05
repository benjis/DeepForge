# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/contracts/review'
require 'deepforge/review/review_output'

RSpec.describe DeepForge::Review do
  describe '.parse_review_output' do
    it 'parses valid JSON review output' do
      json = {
        'findings' => [],
        'overallCorrectness' => 'patch is correct',
        'overallExplanation' => 'All good',
        'overallConfidenceScore' => 0.9
      }.to_json

      output = described_class.parse_review_output(json)
      expect(output).to be_a(DeepForge::Contracts::ReviewOutput)
      expect(output.overall_correctness).to eq('patch is correct')
      expect(output.overall_confidence_score).to eq(0.9)
    end

    it 'parses JSON embedded in text' do
      text = "Here is my review:\n#{{
        'findings' => [],
        'overallCorrectness' => 'patch is correct',
        'overallExplanation' => 'Looks fine',
        'overallConfidenceScore' => 0.8
      }.to_json}\nDone."

      output = described_class.parse_review_output(text)
      expect(output.overall_explanation).to eq('Looks fine')
    end

    it 'returns fallback for non-JSON text' do
      output = described_class.parse_review_output('This is not JSON')
      expect(output.findings).to eq([])
      expect(output.overall_explanation).to eq('This is not JSON')
      expect(output.overall_confidence_score).to eq(0.0)
    end

    it 'returns fallback for empty text' do
      output = described_class.parse_review_output('')
      expect(output.overall_explanation).to include('structured response')
    end

    it 'normalizes snake_case and camelCase keys' do
      json = {
        'findings' => [{
          'title' => '[P1] Bug',
          'body' => 'desc',
          'confidence_score' => 0.8,
          'priority' => 1,
          'code_location' => {
            'absolute_file_path' => '/file.rb',
            'line_range' => { 'start' => 1, 'end' => 5 }
          }
        }],
        'overall_correctness' => 'patch is incorrect',
        'overall_explanation' => 'Found a bug',
        'overall_confidence_score' => 0.7
      }.to_json

      output = described_class.parse_review_output(json)
      expect(output.findings.length).to eq(1)
      expect(output.findings.first.title).to eq('[P1] Bug')
      expect(output.findings.first.code_location.line_range.start).to eq(1)
    end
  end

  describe '.render_review_output' do
    it 'renders output with no findings' do
      output = DeepForge::Contracts::ReviewOutput.new(
        findings: [],
        overall_correctness: 'patch is correct',
        overall_explanation: 'Looks good',
        overall_confidence_score: 0.9
      )

      text = described_class.render_review_output(output)
      expect(text).to include('Looks good')
      expect(text).to include('Overall correctness: patch is correct')
      expect(text).to include('No review findings')
    end

    it 'renders output with findings' do
      finding = DeepForge::Contracts::ReviewFinding.new(
        title: '[P1] Bug',
        body: 'Description of bug',
        confidence_score: 0.85,
        priority: 1,
        code_location: DeepForge::Contracts::ReviewCodeLocation.new(
          absolute_file_path: '/app/file.rb',
          line_range: DeepForge::Contracts::ReviewLineRange.new(start: 10, end: 15)
        )
      )
      output = DeepForge::Contracts::ReviewOutput.new(
        findings: [finding],
        overall_correctness: 'patch is incorrect',
        overall_explanation: 'Found issues',
        overall_confidence_score: 0.8
      )

      text = described_class.render_review_output(output)
      expect(text).to include('Full review comments')
      expect(text).to include('[P1] Bug')
      expect(text).to include('/app/file.rb:10-15')
      expect(text).to include('Description of bug')
    end
  end
end
