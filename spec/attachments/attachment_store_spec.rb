# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe DeepForge::Attachments::FileAttachmentStore do
  subject(:store) { described_class.new(root_dir: tmpdir, config: config, now_iso: now_iso) }

  let(:tmpdir) { Dir.mktmpdir }
  let(:config) do
    {
      enabled: true, allowed_mime_types: %w[image/png image/jpeg image/webp],
      max_image_bytes: 1_000_000, max_image_dimension: 4096,
      text_fallback_max_base64_bytes: 500_000, text_fallback_max_image_dimension: 1024,
      text_fallback_preferred_mime_type: 'image/png'
    }
  end
  let(:now_iso) { -> { '2024-01-15T12:00:00Z' } }

  after { FileUtils.rm_rf(tmpdir) }

  def minimal_png(width: 2, height: 2)
    header = [
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, width, 0x00, 0x00, 0x00, height,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde
    ].pack('C*')
    header + ("\x00" * 50)
  end

  def minimal_jpeg = "\xFF\xD8\xFF\xE0#{"\x00" * 50}"
  def minimal_webp = "RIFF\u0000\u0000\u0000\u0000WEBP#{"\x00" * 50}"

  describe '#create' do
    it 'creates a PNG attachment and returns metadata' do
      data = minimal_png
      result = store.create(data: data, name: 'test.png', thread_id: 't1')
      expect(result.id).to start_with('att_')
      expect(result.mime_type).to eq('image/png')
      expect(result.byte_size).to eq(data.bytesize)
      expect(result.thread_ids).to include('t1')
    end

    it 'creates JPEG and WebP attachments' do
      expect(store.create(data: minimal_jpeg, name: 'a.jpg').mime_type).to eq('image/jpeg')
      expect(store.create(data: minimal_webp, name: 'a.webp').mime_type).to eq('image/webp')
    end

    it 'writes files to disk' do
      result = store.create(data: minimal_png, name: 'test.png')
      expect(File.exist?(File.join(tmpdir, "#{result.id}.bin"))).to be true
      expect(File.exist?(File.join(tmpdir, "#{result.id}.json"))).to be true
    end

    it 'extracts PNG dimensions' do
      result = store.create(data: minimal_png(width: 100, height: 200), name: 'test.png')
      expect(result.width).to eq(100)
      expect(result.height).to eq(200)
    end

    it 'returns existing attachment for duplicate content' do
      data = minimal_png
      first = store.create(data: data, name: 'first.png', thread_id: 't1')
      second = store.create(data: data, name: 'second.png', thread_id: 't2')
      expect(first.id).to eq(second.id)
      expect(second.thread_ids).to include('t1')
      expect(second.thread_ids).to include('t2')
    end

    it 'rejects non-image data' do
      expect do
        store.create(data: 'not an image', name: 'bad.txt')
      end.to raise_error(ArgumentError, /unsupported image MIME type/)
    end

    it 'rejects mismatched MIME type' do
      expect do
        store.create(data: minimal_png, name: 'test.png',
                     mime_type: 'image/jpeg')
      end.to raise_error(ArgumentError, /declared MIME type does not match/)
    end

    it 'rejects oversized images' do
      small_store = described_class.new(root_dir: tmpdir, config: config.merge(max_image_bytes: 1), now_iso: now_iso)
      expect { small_store.create(data: minimal_png, name: 'big.png') }.to raise_error(ArgumentError, /byte limit/)
    end
  end

  describe '#get' do
    it 'returns metadata for existing attachment' do
      created = store.create(data: minimal_png, name: 'test.png')
      expect(store.get(created.id).name).to eq('test.png')
    end

    it 'returns nil for nonexistent' do
      expect(store.get('att_nonexistent')).to be_nil
    end
  end

  describe '#resolve_content' do
    it 'returns data for authorized scope' do
      data = minimal_png
      created = store.create(data: data, name: 'test.png', thread_id: 't1')
      expect(store.resolve_content(created.id, { thread_id: 't1' }).data).to eq(data)
    end

    it 'raises when not found' do
      expect { store.resolve_content('att_nonexistent', {}) }.to raise_error(RuntimeError, /not found/)
    end

    it 'raises when not authorized' do
      created = store.create(data: minimal_png, name: 'test.png', thread_id: 't1')
      expect { store.resolve_content(created.id, { thread_id: 't2' }) }.to raise_error(RuntimeError, /not authorized/)
    end

    it 'allows access when no scope restrictions' do
      created = store.create(data: minimal_png, name: 'test.png')
      expect(store.resolve_content(created.id, { thread_id: 'any' })).not_to be_nil
    end
  end

  describe '#text_fallback_policy' do
    it 'returns policy from config' do
      policy = store.text_fallback_policy
      expect(policy[:text_fallback_max_base64_bytes]).to eq(500_000)
    end
  end

  describe '#diagnostics' do
    it 'reports count and total bytes' do
      expect(store.diagnostics[:count]).to eq(0)
      store.create(data: minimal_png, name: 'test.png')
      expect(store.diagnostics[:count]).to eq(1)
    end
  end
end

RSpec.describe DeepForge::Attachments::AttachmentStore do
  it 'raises NotImplementedError for abstract methods' do
    store = described_class.new
    expect { store.create({}) }.to raise_error(NotImplementedError)
    expect { store.get('id') }.to raise_error(NotImplementedError)
    expect { store.resolve_content('id', {}) }.to raise_error(NotImplementedError)
    expect { store.text_fallback_policy }.to raise_error(NotImplementedError)
    expect { store.diagnostics }.to raise_error(NotImplementedError)
  end
end
