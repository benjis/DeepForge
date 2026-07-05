# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts::RuntimeInfoResponse do
  it 'supports keyword init' do
    resp = described_class.new(
      host: 'localhost', port: 8080, data_dir: '/data',
      model: 'deepseek-chat', approval_policy: 'on-request',
      sandbox_mode: 'workspace-write', started_at: '2025-01-01T00:00:00Z', pid: 1234
    )
    expect(resp.host).to eq('localhost')
    expect(resp.port).to eq(8080)
    expect(resp.pid).to eq(1234)
  end

  it 'defaults optional fields to nil' do
    resp = described_class.new
    expect(resp.host).to be_nil
    expect(resp.capabilities).to be_nil
  end
end
