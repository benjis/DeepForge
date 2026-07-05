# frozen_string_literal: true

require 'securerandom'
require_relative '../ports/id_generator'

module DeepForge
  module Adapters
    class RandomIdGenerator < DeepForge::Ports::IdGenerator
      def next(prefix = 'id')
        "#{prefix}_#{SecureRandom.hex(8)}"
      end

      alias generate next
    end
  end
end
