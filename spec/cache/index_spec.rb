# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DeepForge autoload: Cache & Memory' do
  it 'loads all cache classes' do
    expect(LruCache).to be_a(Class)
    expect(TtlLruCache).to be_a(Class)
    expect(ImmutablePrefixBuilder).to be_a(Module)
    expect(PrefixVolatility).to be_a(Module)
    expect(ToolCatalogFingerprint).to be_a(Module)
  end

  it 'loads all memory classes' do
    expect(MemoryStore).to be_a(Module)
    expect(FileMemoryStore).to be_a(Class)
  end
end
