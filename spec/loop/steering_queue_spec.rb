# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/steering_queue'

RSpec.describe DeepForge::Loop::SteeringQueue do
  subject(:queue) { described_class.new }

  describe '#enqueue' do
    it 'adds text to the buffer' do
      queue.enqueue('t1', 'hello')
      expect(queue.peek).to eq(['hello'])
    end

    it 'strips whitespace from text' do
      queue.enqueue('t1', '  hello  ')
      expect(queue.peek).to eq(['hello'])
    end

    it 'ignores empty text' do
      queue.enqueue('t1', '')
      expect(queue.peek).to eq([])
    end

    it 'ignores whitespace-only text' do
      queue.enqueue('t1', '   ')
      expect(queue.peek).to eq([])
    end

    it 'clears buffer when turn_id changes' do
      queue.enqueue('t1', 'first')
      queue.enqueue('t2', 'second')
      expect(queue.peek).to eq(['second'])
    end

    it 'keeps buffer on same turn_id' do
      queue.enqueue('t1', 'first')
      queue.enqueue('t1', 'second')
      expect(queue.peek).to eq(%w[first second])
    end
  end

  describe '#drain' do
    it 'returns all buffered text and clears' do
      queue.enqueue('t1', 'hello')
      queue.enqueue('t1', 'world')
      result = queue.drain
      expect(result).to eq(%w[hello world])
      expect(queue.peek).to eq([])
    end

    it 'returns empty array when buffer is empty' do
      expect(queue.drain).to eq([])
    end
  end

  describe '#peek' do
    it 'returns buffered text without clearing' do
      queue.enqueue('t1', 'hello')
      expect(queue.peek).to eq(['hello'])
      expect(queue.peek).to eq(['hello'])
    end

    it 'returns a copy of the buffer' do
      queue.enqueue('t1', 'hello')
      result = queue.peek
      queue.enqueue('t1', 'world')
      expect(result).to eq(['hello'])
    end
  end

  describe '#clear' do
    it 'clears the buffer and resets turn_id' do
      queue.enqueue('t1', 'hello')
      queue.clear
      expect(queue.peek).to eq([])
    end
  end

  describe '#set_turn' do
    it 'clears buffer when turn_id changes' do
      queue.enqueue('t1', 'hello')
      queue.set_turn('t2')
      expect(queue.peek).to eq([])
    end

    it 'keeps buffer when turn_id is same' do
      queue.enqueue('t1', 'hello')
      queue.set_turn('t1')
      expect(queue.peek).to eq(['hello'])
    end

    it 'sets turn_id for new queue' do
      queue.set_turn('t1')
      queue.enqueue('t1', 'hello')
      expect(queue.peek).to eq(['hello'])
    end
  end
end
