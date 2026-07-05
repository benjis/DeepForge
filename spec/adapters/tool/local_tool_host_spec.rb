# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/deepforge/adapters/tool/local_tool_host'

RSpec.describe DeepForge::Adapters::Tool::LocalToolHost do
  let(:echo_tool) do
    described_class.define_tool(
      name: 'echo',
      description: 'Echo input',
      tool_kind: DeepForge::Adapters::Tool::TOOL_KIND_TOOL_CALL,
      input_schema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] },
      policy: DeepForge::Adapters::Tool::POLICY_AUTO,
      execute: ->(args, _ctx, &_blk) { { output: { echoed: args[:text] || '' } } }
    )
  end

  describe '.define_tool' do
    it 'creates a LocalTool from a hash' do
      tool = described_class.define_tool(
        name: 'test',
        description: 'test tool',
        input_schema: { type: 'object' },
        tool_kind: 'tool_call',
        policy: 'auto',
        execute: ->(_args, _ctx) { { output: {} } }
      )
      expect(tool).to be_a(DeepForge::Adapters::Tool::LocalTool)
      expect(tool.name).to eq('test')
      expect(tool.description).to eq('test tool')
      expect(tool.tool_kind).to eq('tool_call')
      expect(tool.policy).to eq('auto')
    end

    it 'applies defaults for tool_kind and policy' do
      tool = described_class.define_tool(
        name: 'test',
        description: 'test',
        input_schema: {},
        execute: ->(_args, _ctx) { { output: {} } }
      )
      expect(tool.tool_kind).to eq(DeepForge::Adapters::Tool::TOOL_KIND_TOOL_CALL)
      expect(tool.policy).to eq(DeepForge::Adapters::Tool::POLICY_ON_REQUEST)
    end
  end

  describe 'policy constants' do
    it 'defines expected policies' do
      expect(DeepForge::Adapters::Tool::POLICY_AUTO).to eq('auto')
      expect(DeepForge::Adapters::Tool::POLICY_ON_REQUEST).to eq('on-request')
      expect(DeepForge::Adapters::Tool::POLICY_SUGGEST).to eq('suggest')
      expect(DeepForge::Adapters::Tool::POLICY_NEVER).to eq('never')
      expect(DeepForge::Adapters::Tool::POLICY_UNTRUSTED).to eq('untrusted')
    end
  end

  describe 'tool kind constants' do
    it 'defines expected tool kinds' do
      expect(DeepForge::Adapters::Tool::TOOL_KIND_TOOL_CALL).to eq('tool_call')
      expect(DeepForge::Adapters::Tool::TOOL_KIND_COMMAND_EXECUTION).to eq('command_execution')
      expect(DeepForge::Adapters::Tool::TOOL_KIND_FILE_CHANGE).to eq('file_change')
    end
  end

  describe 'ECHO_TOOL' do
    it 'is defined as a LocalTool' do
      expect(DeepForge::Adapters::Tool::ECHO_TOOL).to be_a(DeepForge::Adapters::Tool::LocalTool)
      expect(DeepForge::Adapters::Tool::ECHO_TOOL.name).to eq('echo')
      expect(DeepForge::Adapters::Tool::ECHO_TOOL.policy).to eq('auto')
    end
  end

  describe 'USER_INPUT_TOOL and REQUEST_USER_INPUT_TOOL' do
    it 'are defined as LocalTools' do
      expect(DeepForge::Adapters::Tool::USER_INPUT_TOOL).to be_a(DeepForge::Adapters::Tool::LocalTool)
      expect(DeepForge::Adapters::Tool::USER_INPUT_TOOL.name).to eq('user_input')
      expect(DeepForge::Adapters::Tool::REQUEST_USER_INPUT_TOOL.name).to eq('request_user_input')
    end
  end

  describe 'LocalToolHostOptions struct' do
    it 'has expected fields' do
      opts = DeepForge::Adapters::Tool::LocalToolHostOptions.new(
        tools: [echo_tool], allow_list: ['echo']
      )
      expect(opts.tools.length).to eq(1)
      expect(opts.allow_list).to eq(['echo'])
    end
  end

  describe 'module-level user input helpers' do
    let(:tool_mod) { DeepForge::Adapters::Tool }

    describe '.normalize_user_input_questions' do
      it 'normalizes valid questions' do
        args = { questions: [{ question: 'What?', options: [{ label: 'Yes' }] }] }
        result = tool_mod.normalize_user_input_questions(args, 'id1', 'fallback')
        expect(result.length).to eq(1)
        expect(result.first[:question]).to eq('What?')
      end

      it 'returns default question for empty input' do
        result = tool_mod.normalize_user_input_questions({}, 'id1', 'fallback')
        expect(result.length).to eq(1)
        expect(result.first[:question]).to eq('fallback')
      end

      it 'filters out questions without a question field' do
        args = { questions: [{ header: 'Q' }] }
        result = tool_mod.normalize_user_input_questions(args, 'id1', 'fallback')
        expect(result.length).to eq(1)
        expect(result.first[:question]).to eq('fallback')
      end
    end

    describe '.normalize_user_input_question' do
      it 'normalizes a valid question hash' do
        value = { question: 'What?', header: 'Q1', id: 'q1', options: [] }
        result = tool_mod.normalize_user_input_question(value, 0, 'fallback')
        expect(result[:question]).to eq('What?')
        expect(result[:header]).to eq('Q1')
        expect(result[:id]).to eq('q1')
      end

      it 'returns nil for non-hash input' do
        expect(tool_mod.normalize_user_input_question('invalid', 0, 'id')).to be_nil
      end

      it 'returns nil for missing question' do
        expect(tool_mod.normalize_user_input_question({ header: 'Q' }, 0, 'id')).to be_nil
      end

      it 'generates defaults for missing fields' do
        result = tool_mod.normalize_user_input_question({ question: 'Yes?' }, 2, 'id1')
        expect(result[:header]).to eq('Question 3')
        expect(result[:id]).to eq('id1_3')
      end
    end

    describe '.normalize_user_input_option' do
      it 'normalizes a valid option hash' do
        result = tool_mod.normalize_user_input_option({ label: 'Yes', description: 'Confirm' })
        expect(result[:label]).to eq('Yes')
        expect(result[:description]).to eq('Confirm')
      end

      it 'returns nil for non-hash' do
        expect(tool_mod.normalize_user_input_option('bad')).to be_nil
      end

      it 'returns nil for empty label' do
        expect(tool_mod.normalize_user_input_option({ label: '' })).to be_nil
      end

      it 'defaults description to empty string' do
        result = tool_mod.normalize_user_input_option({ label: 'OK' })
        expect(result[:description]).to eq('')
      end
    end
  end
end
