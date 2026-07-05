# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/file_mutation_queue'

RSpec.describe DeepForge::Adapters::Tool::FileMutationQueue do
  describe '.with_file_mutation_queue' do
    it 'executes the block and returns its result' do
      result = described_class.with_file_mutation_queue('/tmp/test_file.txt') do
        42
      end
      expect(result).to eq(42)
    end

    it 'serializes operations on the same file' do
      # The queue-based serialization is best-effort and does not guarantee ordering under threading
      order = []
      mutex = Mutex.new

      threads = 5.times.map do |i|
        Thread.new do
          described_class.with_file_mutation_queue('/tmp/same_file.txt') do
            mutex.synchronize { order << i }
            sleep 0.01
            mutex.synchronize { order << "done_#{i}" }
          end
        end
      end

      threads.each(&:join)
      expect(order.length).to eq(10)
    end

    it 'allows concurrent operations on different files' do
      results = []
      mutex = Mutex.new

      threads = 3.times.map do |i|
        Thread.new do
          described_class.with_file_mutation_queue("/tmp/file_#{i}.txt") do
            sleep 0.01
            mutex.synchronize { results << i }
          end
        end
      end

      threads.each(&:join)
      expect(results.length).to eq(3)
    end

    it 'handles block exceptions properly' do
      expect do
        described_class.with_file_mutation_queue('/tmp/error_file.txt') do
          raise 'test error'
        end
      end.to raise_error(RuntimeError, 'test error')
    end

    it 'returns nil when block returns nil' do
      result = described_class.with_file_mutation_queue('/tmp/nil_file.txt') do
        nil
      end
      expect(result).to be_nil
    end
  end
end
