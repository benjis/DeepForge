# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge do
  describe 'module definition' do
    it 'is defined as a module' do
      expect(described_class).to be_a(Module)
    end
  end
end
