# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeepForge::Ports::ModelClient do
  subject(:client) { described_class.new(provider: 'test', model: 'test-model') }

  it 'exposes provider and model' do
    expect(client.provider).to eq('test')
    expect(client.model).to eq('test-model')
  end

  it 'raises NotImplementedError on #stream' do
    expect { client.stream(nil) }.to raise_error(NotImplementedError)
  end
end

RSpec.describe DeepForge::Ports::ModelStreamChunk do
  describe '.assistant_text_delta' do
    it 'creates a delta chunk' do
      chunk = described_class.assistant_text_delta(text: 'hello')
      expect(chunk).to eq(kind: 'assistant_text_delta', text: 'hello')
    end
  end

  describe '.assistant_reasoning_delta' do
    it 'creates a reasoning delta chunk' do
      chunk = described_class.assistant_reasoning_delta(text: 'thinking')
      expect(chunk).to eq(kind: 'assistant_reasoning_delta', text: 'thinking')
    end
  end

  describe '.tool_call_delta' do
    it 'creates minimal delta with call_id only' do
      chunk = described_class.tool_call_delta(call_id: 'c1')
      expect(chunk).to eq(kind: 'tool_call_delta', call_id: 'c1')
    end

    it 'includes tool_name and arguments_delta when provided' do
      chunk = described_class.tool_call_delta(call_id: 'c1', tool_name: 'bash', arguments_delta: '{"cmd')
      expect(chunk[:tool_name]).to eq('bash')
      expect(chunk[:arguments_delta]).to eq('{"cmd')
    end
  end

  describe '.tool_call_complete' do
    it 'creates a complete chunk' do
      chunk = described_class.tool_call_complete(call_id: 'c1', tool_name: 'bash', arguments: { cmd: 'ls' })
      expect(chunk).to eq(kind: 'tool_call_complete', call_id: 'c1', tool_name: 'bash', arguments: { cmd: 'ls' })
    end
  end

  describe '.usage' do
    it 'creates a usage chunk' do
      snap = OpenStruct.new
      chunk = described_class.usage(usage: snap)
      expect(chunk).to eq(kind: 'usage', usage: snap)
    end
  end

  describe '.completed' do
    it 'creates a completed chunk' do
      chunk = described_class.completed(stop_reason: 'stop')
      expect(chunk).to eq(kind: 'completed', stop_reason: 'stop')
    end
  end

  describe '.error' do
    it 'creates an error chunk without code' do
      chunk = described_class.error(message: 'fail')
      expect(chunk).to eq(kind: 'error', message: 'fail')
    end

    it 'includes code when provided' do
      chunk = described_class.error(message: 'fail', code: 'E001')
      expect(chunk[:code]).to eq('E001')
    end
  end
end

RSpec.describe DeepForge::Ports::ModelRequest do
  it 'supports keyword init' do
    req = described_class.new(thread_id: 't1', turn_id: 'tr1', model: 'm', stream: true)
    expect(req.thread_id).to eq('t1')
    expect(req.stream).to be(true)
  end
end

RSpec.describe DeepForge::Ports::ModelInputAttachment do
  it 'supports keyword init' do
    att = described_class.new(id: 'a1', name: 'file.png', mime_type: 'image/png', data_base64: 'abc')
    expect(att.id).to eq('a1')
  end
end

RSpec.describe DeepForge::Ports::ModelToolSpec do
  it 'supports keyword init' do
    spec = described_class.new(name: 'bash', description: 'run commands', input_schema: {}, tool_kind: 'tool_call')
    expect(spec.name).to eq('bash')
  end
end
