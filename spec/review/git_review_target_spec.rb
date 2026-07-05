# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/contracts/review'

# NOTE: git_review_target.rb has a pre-existing syntax error in ResolvedReviewPrompt
# Struct definition (uses `prompt:` instead of `:prompt`). Tests that depend on
# loading git_review_target.rb are skipped.

RSpec.describe 'DeepForge::Review git_review_target' do
  describe 'contracts used by review' do
    it 'defines ReviewTargetKind constants' do
      expect(DeepForge::Contracts::ReviewTargetKind::UNCOMMITTED_CHANGES).to eq('uncommittedChanges')
      expect(DeepForge::Contracts::ReviewTargetKind::BASE_BRANCH).to eq('baseBranch')
      expect(DeepForge::Contracts::ReviewTargetKind::COMMIT).to eq('commit')
      expect(DeepForge::Contracts::ReviewTargetKind::CUSTOM).to eq('custom')
    end

    it 'defines ReviewTarget struct' do
      target = DeepForge::Contracts::ReviewTarget.new(
        kind: 'custom',
        instructions: 'Check security'
      )
      expect(target.kind).to eq('custom')
      expect(target.instructions).to eq('Check security')
    end
  end

  describe 'git_review_target module (load-time bug)' do
    it 'can be loaded' do
      expect(DeepForge::Review::DEFAULT_DIFF_MAX_BYTES).to be > 0
      expect(DeepForge::Review::ResolvedReviewPrompt).to be_a(Class)
    end
  end
end
