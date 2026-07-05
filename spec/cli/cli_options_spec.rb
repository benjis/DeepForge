# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge::CLI module constants' do
  it 'defines ServeExitCode constants when cli_options is loaded' do
    expect(DeepForge::CLI::ServeExitCode::OK).to eq(0)
    expect(DeepForge::CLI::ServeExitCode::USAGE).to eq(64)
    expect(DeepForge::CLI::ServeExitCode::CONFIG).to eq(78)
    expect(DeepForge::CLI::ServeExitCode::RUNTIME).to eq(70)
  end

  it 'creates DEFAULT_SERVE_OPTIONS' do
    expect(DeepForge::CLI::DEFAULT_SERVE_OPTIONS).to be_a(DeepForge::CLI::ServeOptions)
    expect(DeepForge::CLI::DEFAULT_SERVE_OPTIONS.host).to eq('127.0.0.1')
    expect(DeepForge::CLI::DEFAULT_SERVE_OPTIONS.port).to eq(8899)
  end
end
