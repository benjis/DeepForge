# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Server do
  describe '.create_deepforge_serve_runtime' do
    it 'is defined as a class method' do
      expect(described_class).to respond_to(:create_deepforge_serve_runtime)
    end
  end
end
