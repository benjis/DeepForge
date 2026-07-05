# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe DeepForge::Skills::SkillRuntime do
  subject(:runtime) { described_class.create(config, options) }

  let(:config) { nil }
  let(:options) { {} }

  describe '.create' do
    it 'creates a disabled runtime by default' do
      rt = described_class.create
      expect(rt.count).to eq(0)
      expect(rt.diagnostics[:enabled]).to be(false)
    end
  end

  describe '#resolve_turn' do
    it 'returns empty resolution when disabled' do
      result = runtime.resolve_turn(prompt: 'hello', workspace: '/tmp')
      expect(result.active_skill_ids).to be_empty
      expect(result.activations).to be_empty
      expect(result.injected_bytes).to eq(0)
    end
  end

  describe '#diagnostics' do
    it 'returns diagnostic hash when disabled' do
      diag = runtime.diagnostics
      expect(diag[:enabled]).to be(false)
      expect(diag[:skills]).to be_empty
      expect(diag[:validation_errors]).to be_empty
    end
  end

  describe '#count' do
    it 'returns zero when no skills loaded' do
      expect(runtime.count).to eq(0)
    end
  end

  describe '#refresh' do
    it 'does not crash when disabled' do
      expect { runtime.refresh }.not_to raise_error
    end
  end

  context 'with legacy SKILL.md' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:skill_dir) { File.join(tmpdir, 'test-skill') }
    let(:config) { { enabled: true, roots: [tmpdir], legacy_skill_md: true } }

    before do
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, 'SKILL.md'), "# Test Skill\n\nThis is a test skill.")
    end

    after { FileUtils.rm_rf(tmpdir) }

    it 'discovers legacy skills' do
      rt = described_class.create(config)
      expect(rt.count).to be >= 1
    end

    it 'loads with correct metadata' do
      skill = described_class.create(config).diagnostics[:skills].first
      expect(skill[:name]).not_to be_nil
      expect(skill[:legacy]).to be(true)
    end

    it 'returns empty resolution for legacy (no triggers)' do
      result = described_class.create(config).resolve_turn(prompt: 'hello', workspace: '/tmp')
      expect(result.active_skill_ids).to be_empty
    end
  end

  context 'with skill.json manifest' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:skill_dir) { File.join(tmpdir, 'json-skill') }
    let(:config) { { enabled: true, roots: [tmpdir], legacy_skill_md: true } }

    before do
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, 'SKILL.md'), '# JSON Skill\n\nSkill body.')
      File.write(File.join(skill_dir, 'skill.json'), JSON.generate({
                                                                     id: 'json-skill', name: 'JSON Skill', description: 'A skill from manifest',
                                                                     version: '1.0.0', entry: 'SKILL.md',
                                                                     triggers: { commands: ['/test'], prompt_patterns: ['test_pattern'], file_types: ['.rb'] },
                                                                     allowed_tools: ['bash'], assets: [], priority: 10
                                                                   }))
    end

    after { FileUtils.rm_rf(tmpdir) }

    it 'loads from manifest' do
      expect(described_class.create(config).count).to be >= 1
    end

    it 'resolves by command trigger' do
      result = described_class.create(config).resolve_turn(prompt: '/test do something', workspace: '/tmp')
      expect(result.active_skill_ids).to include('json-skill')
    end

    it 'resolves by prompt pattern' do
      result = described_class.create(config).resolve_turn(prompt: 'test_pattern found', workspace: '/tmp')
      expect(result.active_skill_ids).to include('json-skill')
    end

    it 'respects active_limit' do
      skill_dir2 = File.join(tmpdir, 'second-skill')
      FileUtils.mkdir_p(skill_dir2)
      File.write(File.join(skill_dir2, 'SKILL.md'), '# Second')
      File.write(File.join(skill_dir2, 'skill.json'), JSON.generate({
                                                                      id: 'second-skill', name: 'Second', description: 'Second',
                                                                      triggers: { commands: ['/second'] }, allowed_tools: [], assets: [], priority: 5
                                                                    }))
      result = described_class.create(config, active_limit: 1).resolve_turn(prompt: '/test something',
                                                                            workspace: '/tmp')
      expect(result.active_skill_ids.length).to eq(1)
    end

    it 'includes allowed tools' do
      result = described_class.create(config).resolve_turn(prompt: '/test do something', workspace: '/tmp')
      expect(result.allowed_tool_names).to include('bash')
    end
  end

  context 'with invalid manifest' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:config) { { enabled: true, roots: [tmpdir], legacy_skill_md: true } }

    before do
      FileUtils.mkdir_p(File.join(tmpdir, 'bad-skill'))
      File.write(File.join(tmpdir, 'bad-skill', 'skill.json'), '{invalid json')
    end

    after { FileUtils.rm_rf(tmpdir) }

    it 'records validation errors' do
      rt = described_class.create(config)
      expect(rt.diagnostics[:validation_errors]).not_to be_empty
    end
  end

  describe '.safe_pattern_matches' do
    it 'handles invalid regex gracefully' do
      expect(runtime.send(:safe_pattern_matches, '[invalid', 'hello')).to be false
    end

    it 'matches case-insensitively' do
      expect(runtime.send(:safe_pattern_matches, 'hello', 'Hello World')).to be true
    end
  end

  describe '.first_markdown_paragraph' do
    it 'extracts first non-empty block after stripping headings' do
      result = described_class.first_markdown_paragraph("# Title\n\nFirst paragraph.\n\nSecond.")
      expect(result).to eq('Title')
    end
  end

  describe '.slug' do
    it 'converts to lowercase with hyphens' do
      expect(described_class.slug('Hello World!')).to eq('hello-world')
    end

    it 'returns "skill" for empty input' do
      expect(described_class.slug('   ')).to eq('skill')
    end
  end

  describe '.normalize_file_type' do
    it 'prepends dot if missing' do
      expect(described_class.normalize_file_type('rb')).to eq('.rb')
    end

    it 'preserves existing dot' do
      expect(described_class.normalize_file_type('.rb')).to eq('.rb')
    end
  end
end
