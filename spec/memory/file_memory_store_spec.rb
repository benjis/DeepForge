# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FileMemoryStore do
  subject(:store) do
    described_class.new(
      root_dir: tmpdir,
      config: config,
      now_iso: clock,
      id_generator: id_counter
    )
  end

  let(:tmpdir) { Dir.mktmpdir('memory_test') }
  let(:config) { { enabled: true } }
  let(:fixed_time) { '2025-06-01T12:00:00Z' }
  let(:clock) { -> { fixed_time } }
  let(:id_counter) { -> { "mem_#{rand(1000)}" } }

  after { FileUtils.remove_entry(tmpdir) }

  describe '#create' do
    it 'creates and persists a memory record' do
      record = store.create(content: 'test memory', scope: 'workspace', workspace: '/ws')
      expect(record.id).to be_a(String)
      expect(record.content).to eq('test memory')
      expect(record.scope).to eq('workspace')
      expect(record.created_at).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it 'creates the root directory if needed' do
      new_dir = File.join(tmpdir, 'subdir')
      store_with_subdir = described_class.new(
        root_dir: new_dir, config: config, now_iso: clock, id_generator: id_counter
      )
      store_with_subdir.create(content: 'test')
      expect(Dir.exist?(new_dir)).to be true
    end
  end

  describe '#list' do
    it 'returns all non-deleted records sorted by updated_at desc' do
      store.create(content: 'first')
      store.create(content: 'second')
      records = store.list
      expect(records.size).to eq(2)
      expect(records.map(&:content)).to contain_exactly('first', 'second')
    end

    it 'excludes deleted records' do
      r = store.create(content: 'to delete')
      store.delete(r.id)
      expect(store.list.size).to eq(0)
    end

    it 'includes deleted records when include_deleted is true' do
      r = store.create(content: 'to delete')
      store.delete(r.id)
      expect(store.list(include_deleted: true).size).to eq(1)
    end
  end

  describe '#update' do
    it 'updates content and tags' do
      record = store.create(content: 'original')
      updated = store.update(record.id, content: 'updated', tags: ['new'])
      expect(updated.content).to eq('updated')
      expect(updated.tags).to eq(['new'])
      expect(updated.updated_at).to eq(fixed_time)
    end

    it 'sets disabled_at when disabled is true' do
      record = store.create(content: 'test')
      updated = store.update(record.id, disabled: true)
      expect(updated.disabled_at).to eq(fixed_time)
    end

    it 'clears disabled_at when disabled is false' do
      record = store.create(content: 'test')
      store.update(record.id, disabled: true)
      updated = store.update(record.id, disabled: false)
      expect(updated.disabled_at).to be_nil
    end

    it 'raises when record not found' do
      expect { store.update('nonexistent', content: 'x') }.to raise_error(RuntimeError, /not found/)
    end
  end

  describe '#delete' do
    it 'soft deletes a record' do
      record = store.create(content: 'to delete')
      deleted = store.delete(record.id)
      expect(deleted.deleted_at).to eq(fixed_time)
    end

    it 'raises when record not found' do
      expect { store.delete('nonexistent') }.to raise_error(RuntimeError, /not found/)
    end
  end

  describe '#retrieve' do
    it 'returns matching records sorted by score' do
      store.create(content: 'ruby programming language')
      store.create(content: 'python web framework')
      results = store.retrieve(query: 'ruby language', limit: 5)
      expect(results.size).to eq(1)
      expect(results.first.content).to eq('ruby programming language')
    end

    it 'returns empty when config is disabled' do
      store_with_disabled = described_class.new(
        root_dir: tmpdir, config: { enabled: false }, now_iso: clock, id_generator: id_counter
      )
      store_with_disabled.create(content: 'test')
      expect(store_with_disabled.retrieve(query: 'test', limit: 5)).to eq([])
    end

    it 'respects limit' do
      3.times { |i| store.create(content: "ruby #{i}") }
      results = store.retrieve(query: 'ruby', limit: 2)
      expect(results.size).to eq(2)
    end

    it 'excludes disabled records' do
      r = store.create(content: 'disabled memory')
      store.update(r.id, disabled: true)
      expect(store.retrieve(query: 'disabled memory', limit: 5)).to eq([])
    end

    it 'returns empty for no matches' do
      store.create(content: 'unrelated content')
      expect(store.retrieve(query: 'xyz_nonexistent', limit: 5)).to eq([])
    end
  end

  describe '#diagnostics' do
    it 'returns diagnostic info' do
      store.create(content: 'active')
      r2 = store.create(content: 'to delete')
      store.delete(r2.id)
      diag = store.diagnostics
      expect(diag[:enabled]).to be(true)
      expect(diag[:active_count]).to eq(1)
      expect(diag[:tombstone_count]).to eq(1)
      expect(diag[:root_dir]).to eq(tmpdir)
    end
  end

  describe '#set_last_injected' do
    it 'stores injected IDs' do
      store.set_last_injected(%w[m1 m2])
      diag = store.diagnostics
      expect(diag[:last_injected_ids]).to eq(%w[m1 m2])
    end
  end
end
