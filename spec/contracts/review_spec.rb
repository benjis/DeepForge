# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts do
  describe 'ReviewTargetKind constants' do
    it 'defines all target kinds' do
      expect(described_class::ReviewTargetKind::UNCOMMITTED_CHANGES).to eq('uncommittedChanges')
      expect(described_class::ReviewTargetKind::BASE_BRANCH).to eq('baseBranch')
      expect(described_class::ReviewTargetKind::COMMIT).to eq('commit')
      expect(described_class::ReviewTargetKind::CUSTOM).to eq('custom')
    end
  end

  describe '.review_target_title' do
    it 'returns title for uncommittedChanges' do
      target = described_class::ReviewTarget.new(kind: 'uncommittedChanges')
      expect(described_class.review_target_title(target)).to eq('Review current changes')
    end

    it 'returns title for baseBranch with branch name' do
      target = described_class::ReviewTarget.new(kind: 'baseBranch', branch: 'main')
      expect(described_class.review_target_title(target)).to eq('Review changes against main')
    end

    it 'returns title for commit with truncated sha' do
      target = described_class::ReviewTarget.new(kind: 'commit', sha: 'abc123def456')
      expect(described_class.review_target_title(target)).to eq('Review commit abc123def456')
    end

    it 'returns title for custom' do
      target = described_class::ReviewTarget.new(kind: 'custom')
      expect(described_class.review_target_title(target)).to eq('Custom code review')
    end
  end

  describe '.review_target_prompt' do
    it 'returns /review for uncommittedChanges' do
      target = described_class::ReviewTarget.new(kind: 'uncommittedChanges')
      expect(described_class.review_target_prompt(target)).to eq('/review')
    end

    it 'returns /review base <branch> for baseBranch' do
      target = described_class::ReviewTarget.new(kind: 'baseBranch', branch: 'develop')
      expect(described_class.review_target_prompt(target)).to eq('/review base develop')
    end

    it 'returns /review commit <sha> for commit' do
      target = described_class::ReviewTarget.new(kind: 'commit', sha: 'abc123')
      expect(described_class.review_target_prompt(target)).to eq('/review commit abc123')
    end

    it 'returns /review <instructions> for custom' do
      target = described_class::ReviewTarget.new(kind: 'custom', instructions: 'focus on security')
      expect(described_class.review_target_prompt(target)).to eq('/review focus on security')
    end
  end

  describe 'ReviewFinding' do
    it 'creates with keyword init' do
      finding = described_class::ReviewFinding.new(
        title: 'Bug', body: 'Found a bug', confidence_score: 0.9, priority: 'high'
      )
      expect(finding.title).to eq('Bug')
      expect(finding.confidence_score).to eq(0.9)
    end
  end

  describe 'ReviewOutput' do
    it 'creates with keyword init' do
      output = described_class::ReviewOutput.new(
        findings: [], overall_correctness: 'good',
        overall_explanation: 'Looks fine', overall_confidence_score: 0.8
      )
      expect(output.overall_correctness).to eq('good')
    end
  end
end
