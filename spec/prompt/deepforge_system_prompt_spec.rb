# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/prompt/deepforge_system_prompt'

RSpec.describe 'DeepForge::Prompt DEEPFORGE_SYSTEM_PROMPT (deepforge_system_prompt.rb)' do
  it 'is defined and non-empty' do
    expect(DeepForge::Prompt::DEEPFORGE_SYSTEM_PROMPT).to be_a(String)
    expect(DeepForge::Prompt::DEEPFORGE_SYSTEM_PROMPT.length).to be > 100
  end

  it 'contains the agent identity' do
    expect(DeepForge::Prompt::DEEPFORGE_SYSTEM_PROMPT).to include('You are DeepForge')
  end
end
