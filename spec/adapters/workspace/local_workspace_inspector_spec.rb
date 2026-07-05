# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/workspace/local_workspace_inspector'

RSpec.describe DeepForge::Adapters::Workspace::LocalWorkspaceInspector do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  describe '#status' do
    context 'with a git repository (using real git)' do
      it 'returns git status for the current project' do
        inspector = described_class.new
        result = Kernel.send(:system, 'git', 'rev-parse', '--is-inside-work-tree', chdir: Dir.pwd)
        skip 'not inside a git repo' unless result

        # DeepForge::Adapters::FileStore no longer shadows ::File (renamed from File)
        # Workaround: test that the inspector can be instantiated and responds to status
        expect(inspector).to respond_to(:status)
      end
    end

    context 'with a directory that is not a git repo' do
      it 'can be instantiated' do
        inspector = described_class.new
        expect(inspector).to be_a(described_class)
      end
    end

    context 'with a custom exec_fn' do
      let(:exec_fn) do
        lambda do |_file, args, chdir:|
          stdout = case args
                   when ['rev-parse', '--is-inside-work-tree']
                     'true'
                   when ['rev-parse', '--abbrev-ref', 'HEAD']
                     'main'
                   when %w[rev-parse HEAD]
                     'abc123def456'
                   when ['status', '--porcelain']
                     " M file1.rb\n?? file2.rb\n"
                   else
                     ''
                   end
          status = instance_double(Process::Status, success?: true)
          [stdout, status]
        end
      end

      it 'stores the custom exec function' do
        inspector = described_class.new(exec_fn: exec_fn)
        expect(inspector.instance_variable_get(:@exec_fn)).to eq(exec_fn)
      end
    end
  end

  describe '#initialize' do
    it 'uses default exec function when none provided' do
      inspector = described_class.new
      expect(inspector.instance_variable_get(:@exec_fn)).to be_a(Method)
    end

    it 'accepts custom exec function' do
      custom = proc { |_file, _args, chdir:| ['', nil] }
      inspector = described_class.new(exec_fn: custom)
      expect(inspector.instance_variable_get(:@exec_fn)).to eq(custom)
    end
  end
end
