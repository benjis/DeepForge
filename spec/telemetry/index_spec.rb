# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge autoload: Telemetry' do
  it 'loads CacheTelemetry' do
    expect(DeepForge::Telemetry::CacheTelemetry).to be_a(Class)
  end

  it 'loads UsageCounter' do
    expect(DeepForge::Telemetry::UsageCounter).to be_a(Class)
  end
end
