# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Contracts::DeepForgeErrorCode do
  it 'defines all error code constants' do
    expect(described_class::VALIDATION_ERROR).to eq('validation_error')
    expect(described_class::NOT_FOUND).to eq('not_found')
    expect(described_class::INTERNAL_ERROR).to eq('internal_error')
    expect(described_class::NOT_IMPLEMENTED).to eq('not_implemented')
    expect(described_class::ABORTED).to eq('aborted')
    expect(described_class::CONFLICT).to eq('conflict')
    expect(described_class::RATE_LIMITED).to eq('rate_limited')
    expect(described_class::APPROVAL_NOT_PENDING).to eq('approval_not_pending')
    expect(described_class::POLICY_BLOCKED).to eq('policy_blocked')
    expect(described_class::MODEL_MODALITY_UNSUPPORTED).to eq('model_modality_unsupported')
  end
end

RSpec.describe DeepForge::Contracts::ErrorBody do
  it 'creates with keyword init' do
    body = described_class.new(code: 'not_found', message: 'not found', details: { id: 't1' })
    expect(body.code).to eq('not_found')
    expect(body.message).to eq('not found')
    expect(body.details).to eq(id: 't1')
  end

  it 'defaults optional fields to nil' do
    body = described_class.new(code: 'error', message: 'fail')
    expect(body.details).to be_nil
  end
end
