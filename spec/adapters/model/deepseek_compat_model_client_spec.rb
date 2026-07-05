# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/model/deepseek_compat_model_client'

# Source code calls requires_reasoning_round_trip (without ?) but the method
# is requires_reasoning_round_trip? — this is a source bug. Define the alias
# so the code can execute during tests.
unless DeepForge::Adapters::Model::DeepseekCompatModelClient.method_defined?(:requires_reasoning_round_trip)
  DeepForge::Adapters::Model::DeepseekCompatModelClient.class_eval do
    alias_method :requires_reasoning_round_trip, :requires_reasoning_round_trip?
  end
end

RSpec.describe DeepForge::Adapters::Model::DeepseekCompatModelClient do
  subject(:client) { described_class.new(config) }

  let(:config) do
    {
      base_url: 'https://api.deepseek.com',
      api_key: 'test-key',
      model: 'deepseek-chat'
    }
  end

  describe '#initialize' do
    it 'sets provider and model from config' do
      expect(client.provider).to eq('deepseek-compat')
      expect(client.model).to eq('deepseek-chat')
    end
  end

  describe '#stream' do
    before do
      allow_any_instance_of(described_class).to receive(:thinking_producer_model?).and_return(false)
    end

    context 'with aborted signal' do
      it 'yields an error chunk when already aborted' do
        signal = double('signal', aborted?: true)
        chunks = []
        client.stream(abort_signal: signal) { |c| chunks << c }
        expect(chunks.length).to eq(1)
        expect(chunks.first[:kind]).to eq('error')
        expect(chunks.first[:message]).to include('aborted')
      end
    end

    context 'with non-streaming JSON response' do
      before do
        config[:non_streaming] = true
        response = instance_double(
          Net::HTTPSuccess,
          body: {
            choices: [{ message: { content: 'Hello' }, finish_reason: 'stop' }],
            usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
          }.to_json,
          content_type: 'application/json'
        )
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(client).to receive(:post_json).and_return(response)
      end

      it 'yields text delta and completed chunks' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        text_chunks = chunks.select { |c| c[:kind] == 'assistant_text_delta' }
        completed = chunks.select { |c| c[:kind] == 'completed' }
        expect(text_chunks.map { |c| c[:text] }.join).to eq('Hello')
        expect(completed.first[:stop_reason]).to eq('stop')
      end

      it 'yields usage chunk when present' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        usage = chunks.select { |c| c[:kind] == 'usage' }
        expect(usage.first[:usage][:prompt_tokens]).to eq(10)
      end
    end

    context 'with HTTP error response' do
      before do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(response).to receive_messages(code: '429', body: 'rate limited')
        allow(client).to receive(:post_json).and_return(response)
      end

      it 'yields error chunk with rate_limited code for 429' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        error = chunks.select { |c| c[:kind] == 'error' }.first
        expect(error[:code]).to eq('rate_limited')
      end
    end

    context 'with connection error' do
      before do
        allow(client).to receive(:post_json).and_raise(StandardError, 'connection refused')
      end

      it 'yields error chunk' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        error = chunks.select { |c| c[:kind] == 'error' }.first
        expect(error[:message]).to include('connection refused')
      end
    end

    context 'with SSE streaming response' do
      let(:sse_body) do
        <<~SSE
          data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}

          data: {"choices":[{"delta":{"content":" world"},"finish_reason":null}]}

          data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

          data: [DONE]

        SSE
      end

      before do
        response = instance_double(Net::HTTPSuccess, body: sse_body, content_type: 'text/event-stream')
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(client).to receive(:post_json).and_return(response)
      end

      it 'yields text deltas from SSE stream' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        text_chunks = chunks.select { |c| c[:kind] == 'assistant_text_delta' }
        expect(text_chunks.map { |c| c[:text] }).to eq(['Hello', ' world'])
      end

      it 'yields completed chunk with stop reason' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        completed = chunks.select { |c| c[:kind] == 'completed' }
        expect(completed.first[:stop_reason]).to eq('stop')
      end
    end

    context 'with tool calls in SSE stream' do
      let(:sse_body) do
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"bash\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}\n\n" \
          "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"command\\\":\\\"ls\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n" \
          "data: [DONE]\n\n"
      end

      before do
        response = instance_double(Net::HTTPSuccess, body: sse_body, content_type: 'text/event-stream')
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(client).to receive(:post_json).and_return(response)
      end

      it 'yields tool_call_complete chunks' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        tool_calls = chunks.select { |c| c[:kind] == 'tool_call_complete' }
        expect(tool_calls.length).to eq(1)
        expect(tool_calls.first[:tool_name]).to eq('bash')
        expect(tool_calls.first[:arguments]).to eq({ 'command' => 'ls' })
      end

      it 'yields completed chunk with tool_calls stop reason' do
        chunks = []
        client.stream({ system_prompt: 'hi', history: [] }) { |c| chunks << c }
        completed = chunks.select { |c| c[:kind] == 'completed' }
        expect(completed.first[:stop_reason]).to eq('tool_calls')
      end
    end

    context 'with tool specs in request' do
      let(:sse_body) { "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n" }

      before do
        response = instance_double(Net::HTTPSuccess, body: sse_body, content_type: 'text/event-stream')
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(client).to receive(:post_json) do |_url, body, _headers, _signal|
          expect(body[:tools]).to be_an(Array)
          expect(body[:tools].first[:function][:name]).to eq('bash')
          response
        end
      end

      it 'includes tools in the request body' do
        chunks = []
        tools = [{ name: 'bash', description: 'run bash', input_schema: { type: 'object' } }]
        client.stream(system_prompt: 'hi', history: [], tools: tools) { |c| chunks << c }
      end
    end

    context 'with attachments' do
      let(:sse_body) { "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n" }

      before do
        response = instance_double(Net::HTTPSuccess, body: sse_body, content_type: 'text/event-stream')
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(client).to receive(:post_json) do |_url, body, _headers, _signal|
          messages = body[:messages]
          user_msg = messages.find { |m| m[:role] == 'user' }
          expect(user_msg[:content]).to be_an(Array) if user_msg
          response
        end
      end

      it 'converts string user content to array with image parts' do
        chunks = []
        attachments = [{ mime_type: 'image/png', data_base64: 'abc123', byte_size: 100 }]
        client.stream(
          system_prompt: 'hi',
          history: [],
          attachments: attachments
        ) { |c| chunks << c }
      end
    end
  end
end
