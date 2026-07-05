# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge autoload: Shared' do
  it 'loads gui_plan module' do # trigger module load
    expect(defined?(DeepForge::Shared::GUI_PLAN_RELATIVE_DIR)).to be_truthy
    expect(defined?(DeepForge::Shared::CreatePlanToolInput)).to be_truthy
  end

  it 'loads todos module' do # trigger module load
    expect(defined?(DeepForge::Shared::TASK_LINE_RE)).to be_truthy
    expect(defined?(DeepForge::Shared::ExtractedPlanTodo)).to be_truthy
  end
end
