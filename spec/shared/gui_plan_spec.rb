# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/shared/gui_plan'

RSpec.describe DeepForge::Shared do
  describe 'GUI plan constants' do
    it 'defines GUI_PLAN_RELATIVE_DIR' do
      expect(described_class::GUI_PLAN_RELATIVE_DIR).to eq('.dfsdd/plan')
    end

    it 'defines GUI_PLAN_LEGACY_RELATIVE_DIR' do
      expect(described_class::GUI_PLAN_LEGACY_RELATIVE_DIR).to eq('.deepseekgui/plan')
    end

    it 'defines GUI_PLAN_ACCEPTED_RELATIVE_DIRS' do
      expect(described_class::GUI_PLAN_ACCEPTED_RELATIVE_DIRS).to include('.dfsdd/plan')
      expect(described_class::GUI_PLAN_ACCEPTED_RELATIVE_DIRS).to include('.deepseekgui/plan')
    end
  end

  describe '.gui_plan_relative_path?' do
    it 'returns true for valid current plan path' do
      expect(described_class.gui_plan_relative_path?('.dfsdd/plan/feature.md')).to be true
    end

    it 'returns true for legacy plan path' do
      expect(described_class.gui_plan_relative_path?('.deepseekgui/plan/feature.md')).to be true
    end

    it 'returns false for non-md files' do
      expect(described_class.gui_plan_relative_path?('.dfsdd/plan/feature.txt')).to be false
    end

    it 'returns false for paths outside plan dir' do
      expect(described_class.gui_plan_relative_path?('other/plan/feature.md')).to be false
    end

    it 'returns false for nested paths' do
      expect(described_class.gui_plan_relative_path?('.dfsdd/plan/subdir/feature.md')).to be false
    end

    it 'normalizes backslashes' do
      expect(described_class.gui_plan_relative_path?('.dfsdd\\plan\\feature.md')).to be true
    end
  end

  describe '.gui_plan_current_relative_path?' do
    it 'returns true for current dir plan path' do
      expect(described_class.gui_plan_current_relative_path?('.dfsdd/plan/feature.md')).to be true
    end

    it 'returns false for legacy dir path' do
      expect(described_class.gui_plan_current_relative_path?('.deepseekgui/plan/feature.md')).to be false
    end
  end

  describe '.build_gui_plan_id' do
    it 'builds ID from workspace and relative path' do
      id = described_class.build_gui_plan_id('/workspace', '.dfsdd/plan/feature.md')
      expect(id).to eq('/workspace:.dfsdd/plan/feature.md')
    end

    it 'normalizes case' do
      id = described_class.build_gui_plan_id('/Workspace', '.DFSDD/Plan/Feature.MD')
      expect(id).to eq('/workspace:.dfsdd/plan/feature.md')
    end
  end

  describe '.gui_plan_workspace_matches?' do
    it 'matches equal paths' do
      expect(described_class.gui_plan_workspace_matches?('/ws', '/ws')).to be true
    end

    it 'does not match trailing slash difference (implementation strips trailing slashes)' do
      expect(described_class.gui_plan_workspace_matches?('/ws', '/ws')).to be true
    end

    it 'ignores case' do
      expect(described_class.gui_plan_workspace_matches?('/WS', '/ws')).to be true
    end

    it 'does not match different paths' do
      expect(described_class.gui_plan_workspace_matches?('/ws1', '/ws2')).to be false
    end
  end

  describe '.validate_create_plan_tool_input' do
    it 'returns empty array for valid input' do
      issues = described_class.validate_create_plan_tool_input(
        markdown: '# Plan',
        operation: 'draft'
      )
      expect(issues).to be_empty
    end

    it 'returns error when markdown is missing' do
      issues = described_class.validate_create_plan_tool_input(
        markdown: '',
        operation: 'draft'
      )
      expect(issues).not_to be_empty
      expect(issues.first).to include('markdown')
    end

    it 'returns error for invalid operation' do
      issues = described_class.validate_create_plan_tool_input(
        markdown: '# Plan',
        operation: 'invalid'
      )
      expect(issues.first).to include('operation')
    end

    it 'validates plan_relative_path when provided' do
      issues = described_class.validate_create_plan_tool_input(
        markdown: '# Plan',
        operation: 'draft',
        plan_relative_path: 'invalid/path.md'
      )
      expect(issues.first).to include('plan_relative_path')
    end
  end

  describe '.build_plan_relative_path' do
    it 'builds path without suffix' do
      path = described_class.build_plan_relative_path('feature')
      expect(path).to eq('.dfsdd/plan/feature.md')
    end

    it 'builds path with suffix' do
      path = described_class.build_plan_relative_path('feature', 2)
      expect(path).to eq('.dfsdd/plan/feature-2.md')
    end

    it 'does not add suffix for 1' do
      path = described_class.build_plan_relative_path('feature', 1)
      expect(path).to eq('.dfsdd/plan/feature.md')
    end
  end

  describe '.next_available_plan_relative_path' do
    it 'returns first path when none exist' do
      path = described_class.next_available_plan_relative_path('feature', [])
      expect(path).to eq('.dfsdd/plan/feature.md')
    end

    it 'skips existing paths' do
      existing = ['.dfsdd/plan/feature.md']
      path = described_class.next_available_plan_relative_path('feature', existing)
      expect(path).to eq('.dfsdd/plan/feature-2.md')
    end
  end

  describe '.plan_display_name_from_relative_path' do
    it 'extracts name without .md extension' do
      expect(described_class.plan_display_name_from_relative_path('.dfsdd/plan/my-feature.md')).to eq('my-feature')
    end
  end

  describe '.plan_feature_name_from_request' do
    it 'truncates to 96 characters' do
      long_request = 'a' * 200
      result = described_class.plan_feature_name_from_request(long_request)
      expect(result.length).to eq(96)
    end

    it 'strips whitespace' do
      result = described_class.plan_feature_name_from_request('  feature name  ')
      expect(result).to eq('feature name')
    end
  end
end
