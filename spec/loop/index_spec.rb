# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge autoload: Loop' do
  it 'defines the Loop module' do
    expect(DeepForge::Loop).to be_a(Module)
  end

  it 'has autoload entries for all loop components' do
    expected_constants = %w[
      AgentLoop ContextCompactor ContextEstimator CompactionMarker
      InflightTracker SteeringQueue ToolStormBreaker ToolCallRepair
      HistoryHealing RequestHistoryHygiene TokenEconomy AutoModelRouter
      ModelContextProfile ModelRequestEstimator AppendOnlySessionLog
      Pipeline
    ]

    expected_constants.each do |name|
      expect(DeepForge::Loop.const_defined?(name)).to be(true),
                                                      "Expected DeepForge::Loop to define #{name}"
    end
  end
end
