# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/create_plan_tool'

RSpec.describe DeepForge::Adapters::Tool::CreatePlanTool do
  describe '.create' do
    it 'returns a tool definition' do
      tool = described_class.create(nil)
      expect(tool[:name]).to eq('create_plan')
      expect(tool[:description]).to include('plan')
      expect(tool[:input_schema][:required]).to include('markdown', 'operation')
    end
  end

  describe '.plan_tool_context_active?' do
    it 'returns truthy when gui_plan is present' do
      expect(described_class).to be_plan_tool_context_active({ gui_plan: {} })
    end

    it 'returns true when thread_mode is plan' do
      expect(described_class.plan_tool_context_active?({ thread_mode: 'plan' })).to be true
    end

    it 'returns false when no context' do
      expect(described_class.plan_tool_context_active?(nil)).to be false
    end

    it 'returns false for non-plan context' do
      expect(described_class.plan_tool_context_active?({ thread_mode: 'code' })).to be false
    end
  end

  describe '.to_relative_path' do
    it 'normalizes backslashes' do
      expect(described_class.to_relative_path('path\\to\\file')).to eq('path/to/file')
    end

    it 'removes leading ./' do
      expect(described_class.to_relative_path('./path/file')).to eq('path/file')
    end

    it 'removes trailing slashes' do
      expect(described_class.to_relative_path('path/file/')).to eq('path/file')
    end
  end

  describe '.plan_directory' do
    it 'returns plan directory path' do
      result = described_class.plan_directory('/workspace')
      expect(result).to eq('/workspace/.dfsdd/plan')
    end
  end

  describe '.assert_within_workspace' do
    it 'passes for path within workspace' do
      expect do
        described_class.assert_within_workspace('/workspace/file.txt', '/workspace')
      end.not_to raise_error
    end

    it 'raises for path escaping workspace' do
      expect do
        described_class.assert_within_workspace('/other/file.txt', '/workspace')
      end.to raise_error(RuntimeError, /escaped/)
    end
  end

  describe '.compute_content_fingerprint' do
    it 'computes hash and bytes' do
      result = described_class.compute_content_fingerprint('hello world')
      expect(result[:hash]).to be_a(String)
      expect(result[:hash].length).to eq(16)
      expect(result[:bytes]).to eq(11)
    end
  end

  describe '.build_temp_path' do
    it 'creates temp path with pid' do
      path = described_class.build_temp_path('/workspace/file.md')
      expect(path).to include('.tmp-')
      expect(path).to end_with('.md')
    end

    it 'handles paths without extension' do
      path = described_class.build_temp_path('/workspace/file')
      expect(path).to include('.tmp-')
    end
  end

  describe '.derive_feature_name' do
    it 'derives name from title' do
      name = described_class.derive_feature_name('My Feature')
      expect(name).to eq('my-feature')
    end

    it 'removes special characters' do
      name = described_class.derive_feature_name('Feature: <test> "hello"')
      expect(name).to eq('feature-test-hello')
    end

    it 'returns plan for empty input' do
      expect(described_class.derive_feature_name('')).to eq('plan')
      expect(described_class.derive_feature_name(nil)).to eq('plan')
    end

    it 'truncates to 96 chars' do
      name = described_class.derive_feature_name('a' * 200)
      expect(name.length).to be <= 96
    end
  end

  describe '.build_gui_plan_id' do
    it 'generates a consistent ID' do
      id1 = described_class.build_gui_plan_id('/workspace', '.dfsdd/plan/test.md')
      id2 = described_class.build_gui_plan_id('/workspace', '.dfsdd/plan/test.md')
      expect(id1).to eq(id2)
      expect(id1.length).to eq(16)
    end
  end

  describe '.gui_plan_relative_path?' do
    it 'validates correct paths' do
      expect(described_class.gui_plan_relative_path?('.dfsdd/plan/test.md')).to be true
    end

    it 'rejects non-plan paths' do
      expect(described_class.gui_plan_relative_path?('other/file.md')).to be false
    end

    it 'rejects non-md files' do
      expect(described_class.gui_plan_relative_path?('.dfsdd/plan/test.txt')).to be false
    end
  end

  describe '.next_available_plan_relative_path' do
    it 'returns first available path' do
      result = described_class.next_available_plan_relative_path('feature', [])
      expect(result).to eq('.dfsdd/plan/feature.md')
    end

    it 'appends number for existing paths' do
      existing = ['.dfsdd/plan/feature.md']
      result = described_class.next_available_plan_relative_path('feature', existing)
      expect(result).to eq('.dfsdd/plan/feature-2.md')
    end
  end

  describe '.error_output' do
    it 'returns error hash' do
      result = described_class.error_output('test error')
      expect(result[:output][:error]).to eq('test error')
      expect(result[:is_error]).to be true
    end
  end
end
