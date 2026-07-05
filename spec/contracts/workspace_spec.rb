# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts::WorkspaceStatus do
  it 'supports keyword init' do
    status = described_class.new(
      path: '/ws', exists: true, is_git_repository: true,
      branch: 'main', head_sha: 'abc123', is_dirty: false,
      file_change_count: 0, checked_at: '2025-01-01T00:00:00Z'
    )
    expect(status.path).to eq('/ws')
    expect(status.is_git_repository).to be(true)
    expect(status.branch).to eq('main')
  end

  it 'defaults optional fields to nil' do
    status = described_class.new(path: '/ws')
    expect(status.branch).to be_nil
    expect(status.head_sha).to be_nil
  end
end
