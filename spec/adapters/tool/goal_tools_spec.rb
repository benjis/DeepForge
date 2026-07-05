# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/goal_tools'

RSpec.describe DeepForge::Adapters::Tool::GoalTools do
  let(:thread_service) { double('thread_service') }

  describe '.build' do
    it 'returns 3 goal tools' do
      tools = described_class.build(thread_service)
      expect(tools.length).to eq(3)
      names = tools.map { |t| t[:name] }
      expect(names).to contain_exactly('get_goal', 'create_goal', 'update_goal')
    end
  end

  describe 'get_goal tool' do
    let(:tool) { described_class.create_get_goal_tool(thread_service) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('get_goal')
      expect(tool[:policy]).to eq('auto')
    end

    it 'returns goal from thread service' do
      allow(thread_service).to receive(:get_goal).with('t1').and_return({
                                                                          objective: 'test', status: 'active'
                                                                        })
      result = tool[:execute].call({}, { thread_id: 't1' })
      expect(result[:output][:goal][:objective]).to eq('test')
    end
  end

  describe 'create_goal tool' do
    let(:tool) { described_class.create_create_goal_tool(thread_service) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('create_goal')
      expect(tool[:input_schema][:required]).to include('objective')
    end

    it 'creates a goal' do
      allow(thread_service).to receive(:get_goal).with('t1').and_return(nil)
      allow(thread_service).to receive(:set_goal).and_return({
                                                               objective: 'test', status: 'active'
                                                             })
      result = tool[:execute].call({ objective: 'test' }, { thread_id: 't1' })
      expect(result[:output][:goal][:objective]).to eq('test')
    end

    it 'returns error for empty objective' do
      result = tool[:execute].call({ objective: '' }, { thread_id: 't1' })
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('objective is required')
    end

    it 'returns error when goal already exists' do
      allow(thread_service).to receive(:get_goal).with('t1').and_return({
                                                                          objective: 'existing', status: 'active'
                                                                        })
      result = tool[:execute].call({ objective: 'new' }, { thread_id: 't1' })
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('already has a goal')
    end

    it 'returns error for invalid token_budget' do
      result = tool[:execute].call({ objective: 'test', token_budget: -5 }, { thread_id: 't1' })
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('token_budget must be')
    end
  end

  describe 'update_goal tool' do
    let(:tool) { described_class.create_update_goal_tool(thread_service) }

    it 'has correct metadata' do
      expect(tool[:name]).to eq('update_goal')
      expect(tool[:input_schema][:required]).to include('status')
    end

    it 'updates goal status to complete' do
      allow(thread_service).to receive(:get_goal).with('t1').and_return({
                                                                          objective: 'test', status: 'active'
                                                                        })
      allow(thread_service).to receive(:set_goal).and_return({
                                                               objective: 'test', status: 'complete'
                                                             })
      result = tool[:execute].call({ status: 'complete' }, { thread_id: 't1' })
      expect(result[:output][:goal][:status]).to eq('complete')
      expect(result[:output][:completion_budget_report]).to eq('Goal achieved. Report final usage from this tool result if relevant.')
    end

    it 'returns error for invalid status' do
      result = tool[:execute].call({ status: 'invalid' }, { thread_id: 't1' })
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('can only mark')
    end

    it 'returns error when no goal exists' do
      allow(thread_service).to receive(:get_goal).with('t1').and_return(nil)
      result = tool[:execute].call({ status: 'complete' }, { thread_id: 't1' })
      expect(result[:is_error]).to be true
      expect(result[:output][:error]).to include('does not have a goal')
    end
  end

  describe '.normalize_token_budget' do
    it 'returns nil for nil' do
      expect(described_class.normalize_token_budget(nil)).to be_nil
    end

    it 'returns positive integer' do
      expect(described_class.normalize_token_budget(100)).to eq(100)
    end

    it 'returns false for non-positive' do
      expect(described_class.normalize_token_budget(0)).to be false
      expect(described_class.normalize_token_budget(-1)).to be false
    end

    it 'returns false for non-integer' do
      expect(described_class.normalize_token_budget('100')).to be false
    end
  end

  describe '.goal_response' do
    it 'generates response with remaining tokens' do
      goal = { objective: 'test', token_budget: 100, tokens_used: 30 }
      result = described_class.goal_response(goal)
      expect(result[:remaining_tokens]).to eq(70)
      expect(result[:goal]).to eq(goal)
    end

    it 'returns nil remaining_tokens when no budget' do
      goal = { objective: 'test' }
      result = described_class.goal_response(goal)
      expect(result[:remaining_tokens]).to be_nil
    end

    it 'returns 0 when budget exceeded' do
      goal = { objective: 'test', token_budget: 100, tokens_used: 150 }
      result = described_class.goal_response(goal)
      expect(result[:remaining_tokens]).to eq(0)
    end

    it 'includes completion report when goal is complete' do
      goal = { objective: 'test', status: 'complete' }
      result = described_class.goal_response(goal, 'report text')
      expect(result[:completion_budget_report]).to eq('report text')
    end
  end

  describe '.error_output' do
    it 'returns error hash' do
      result = described_class.error_output('test')
      expect(result[:output][:error]).to eq('test')
      expect(result[:is_error]).to be true
    end
  end
end
