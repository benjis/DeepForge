# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'
require 'deepforge/server/routes/runtime_error'
require 'deepforge/server/routes/review'

RSpec.describe DeepForge::Server::Routes::Review do
  let(:turn_service) { double('TurnService') }

  describe '.review_target_title' do
    it 'returns "Code Review" for code target' do
      expect(described_class.review_target_title('code')).to eq('Code Review')
    end

    it 'returns "Plan Review" for plan target' do
      expect(described_class.review_target_title('plan')).to eq('Plan Review')
    end

    it 'returns "Security Review" for security target' do
      expect(described_class.review_target_title('security')).to eq('Security Review')
    end

    it 'returns "Review" for unknown target' do
      expect(described_class.review_target_title('other')).to eq('Review')
    end
  end

  describe '.review_target_prompt' do
    it 'returns code review prompt' do
      expect(described_class.review_target_prompt('code')).to include('code')
    end

    it 'returns plan review prompt' do
      expect(described_class.review_target_prompt('plan')).to include('plan')
    end

    it 'returns security review prompt' do
      expect(described_class.review_target_prompt('security')).to include('security')
    end

    it 'returns generic prompt for unknown target' do
      expect(described_class.review_target_prompt('other')).to eq('Perform a review.')
    end
  end

  describe '.make_review_item' do
    it 'creates a review item hash' do
      item = described_class.make_review_item(
        id: 'item_1',
        threadId: 't1',
        turnId: 'turn1',
        target: { 'kind' => 'code' },
        title: 'Review',
        status: 'running'
      )

      expect(item[:id]).to eq('item_1')
      expect(item[:kind]).to eq('review')
      expect(item[:status]).to eq('running')
    end
  end

  describe '.start_review' do
    it 'returns validation error when target is missing' do
      request = { body: '{}' }
      response = described_class.start_review(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end

    it 'returns validation error when target.kind is missing' do
      request = { body: '{"target":{}}' }
      response = described_class.start_review(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end

    it 'returns validation error for invalid target.kind' do
      request = { body: '{"target":{"kind":"invalid"}}' }
      response = described_class.start_review(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end

    it 'validates branch is required for baseBranch kind' do
      request = { body: '{"target":{"kind":"baseBranch"}}' }
      response = described_class.start_review(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end

    it 'validates sha is required for commit kind' do
      request = { body: '{"target":{"kind":"commit"}}' }
      response = described_class.start_review(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end

    it 'validates instructions is required for custom kind' do
      request = { body: '{"target":{"kind":"custom"}}' }
      response = described_class.start_review(turn_service, 't1', request)
      expect(response.status).to eq(400)
    end
  end
end
