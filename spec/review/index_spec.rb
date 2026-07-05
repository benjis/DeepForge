# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge autoload: Review' do
  it 'loads review_output module' do  # trigger module load
    expect(defined?(DeepForge::Review.parse_review_output)).to be_truthy
    expect(defined?(DeepForge::Review.render_review_output)).to be_truthy
  end

  it 'loads review_prompt module' do  # trigger module load
    expect(defined?(DeepForge::Review::DEEPFORGE_REVIEW_PROMPT)).to be_truthy
  end
end
