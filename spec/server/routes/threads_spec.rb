# frozen_string_literal: true

require 'spec_helper'
require 'deepforge/server/response'
require 'deepforge/server/read_json_body'
require 'deepforge/server/routes/runtime_error'
require 'deepforge/server/routes/threads'

RSpec.describe DeepForge::Server::Routes::Threads do
  let(:thread_service) { double('ThreadService') }

  describe '.parse_boolean' do
    it 'returns true for truthy strings' do
      expect(described_class.parse_boolean('true')).to be true
      expect(described_class.parse_boolean('1')).to be true
      expect(described_class.parse_boolean('yes')).to be true
      expect(described_class.parse_boolean('on')).to be true
    end

    it 'returns false for falsy strings' do
      expect(described_class.parse_boolean('false')).to be false
      expect(described_class.parse_boolean('0')).to be false
      expect(described_class.parse_boolean('no')).to be false
      expect(described_class.parse_boolean('off')).to be false
    end

    it 'returns the original value for unrecognized strings' do
      expect(described_class.parse_boolean('maybe')).to eq('maybe')
    end

    it 'returns non-string values unchanged' do
      expect(described_class.parse_boolean(true)).to be true
      expect(described_class.parse_boolean(nil)).to be_nil
    end
  end

  describe '.parse_list_threads_options' do
    it 'parses limit parameter' do
      result = described_class.parse_list_threads_options({ 'limit' => '10' })
      expect(result[:limit]).to eq(10)
    end

    it 'parses search parameter' do
      result = described_class.parse_list_threads_options({ 'search' => 'test' })
      expect(result[:search]).to eq('test')
    end

    it 'returns empty hash for empty params' do
      result = described_class.parse_list_threads_options({})
      expect(result).to eq({})
    end
  end

  describe '.list_threads' do
    it 'returns threads list' do
      threads = [{ id: 't1', title: 'Test' }]
      allow(thread_service).to receive(:list).and_return(threads)

      request = { url: 'http://localhost/v1/threads' }
      response = described_class.list_threads(thread_service, request)

      expect(response).to be_a(DeepForge::Server::JsonResponse)
      body = JSON.parse(response.body)
      expect(body['threads'].first['id']).to eq('t1')
    end
  end

  describe '.create_thread' do
    it 'creates a thread with valid body' do
      thread = { id: 't1', title: 'Test', workspace: '/ws', model: 'm1' }
      allow(thread_service).to receive(:create).and_return(thread)

      request = { body: '{"workspace":"/ws","model":"m1","title":"Test"}' }
      response = described_class.create_thread(thread_service, request)
      expect(response.status).to eq(201)
    end

    it 'returns validation error when workspace is missing' do
      request = { body: '{"model":"m1"}' }
      response = described_class.create_thread(thread_service, request)
      expect(response.status).to eq(400)
    end

    it 'returns error for invalid JSON' do
      request = { body: 'not json' }
      response = described_class.create_thread(thread_service, request)
      expect(response.status).to eq(400)
    end
  end

  describe '.get_thread' do
    it 'returns the thread when found' do
      thread = { id: 't1', title: 'Test', turns: [] }
      allow(thread_service).to receive(:get).with('t1').and_return(thread)

      response = described_class.get_thread(thread_service, 't1')
      body = JSON.parse(response.body)
      expect(body['id']).to eq('t1')
    end

    it 'returns 404 when thread not found' do
      allow(thread_service).to receive(:get).with('missing').and_return(nil)

      response = described_class.get_thread(thread_service, 'missing')
      expect(response.status).to eq(404)
    end
  end

  describe '.delete_thread' do
    it 'returns deleted confirmation' do
      allow(thread_service).to receive(:delete).with('t1').and_return(true)

      response = described_class.delete_thread(thread_service, 't1')
      body = JSON.parse(response.body)
      expect(body['deleted']).to be true
    end

    it 'returns 404 when thread not found' do
      allow(thread_service).to receive(:delete).with('missing').and_return(false)

      response = described_class.delete_thread(thread_service, 'missing')
      expect(response.status).to eq(404)
    end
  end

  describe '.fork_thread' do
    it 'forks a thread successfully' do
      forked = { id: 't2', title: 'Test (fork)' }
      allow(thread_service).to receive(:fork).and_return(forked)

      response = described_class.fork_thread(thread_service, 't1')
      expect(response.status).to eq(201)
    end
  end

  describe '.get_thread_goal' do
    it 'returns goal when thread exists' do
      allow(thread_service).to receive(:get_goal).with('t1').and_return(nil)

      response = described_class.get_thread_goal(thread_service, 't1')
      body = JSON.parse(response.body)
      expect(body).to have_key('goal')
    end

    it 'returns 404 when thread not found' do
      allow(thread_service).to receive(:get_goal).with('missing').and_raise(StandardError, 'not found')

      response = described_class.get_thread_goal(thread_service, 'missing')
      expect(response.status).to eq(404)
    end
  end

  describe '.get_thread_todos' do
    it 'returns todos list' do
      allow(thread_service).to receive(:get_todos).with('t1').and_return([])

      response = described_class.get_thread_todos(thread_service, 't1')
      body = JSON.parse(response.body)
      expect(body['todos']).to eq([])
    end
  end

  describe '.clear_thread_goal' do
    it 'clears the goal' do
      allow(thread_service).to receive(:clear_goal).with('t1').and_return(true)

      response = described_class.clear_thread_goal(thread_service, 't1')
      body = JSON.parse(response.body)
      expect(body['cleared']).to be true
    end
  end

  describe '.clear_thread_todos' do
    it 'clears the todos' do
      allow(thread_service).to receive(:clear_todos).with('t1').and_return(true)

      response = described_class.clear_thread_todos(thread_service, 't1')
      body = JSON.parse(response.body)
      expect(body['cleared']).to be true
    end
  end
end
