# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deepforge/loop/tool_result_image'

RSpec.describe DeepForge::Loop::ToolResultImage do
  describe '::IMAGE_TOOL_RESULT_TOKEN_ESTIMATE' do
    it 'is 1200' do
      expect(described_class::IMAGE_TOOL_RESULT_TOKEN_ESTIMATE).to eq(1_200)
    end
  end

  describe '::MODEL_VISIBLE_IMAGE_KINDS' do
    it 'includes image and computer_screenshot' do
      expect(described_class::MODEL_VISIBLE_IMAGE_KINDS).to include('image')
      expect(described_class::MODEL_VISIBLE_IMAGE_KINDS).to include('computer_screenshot')
    end
  end

  describe '.extract_tool_result_images' do
    it 'returns empty for nil' do
      expect(described_class.extract_tool_result_images(nil)).to eq([])
    end

    it 'returns empty for string' do
      expect(described_class.extract_tool_result_images('text')).to eq([])
    end

    it 'returns empty for non-visible kind' do
      output = { kind: 'text', data_base64: 'abc', mime_type: 'image/png' }
      expect(described_class.extract_tool_result_images(output)).to eq([])
    end

    it 'extracts image from read tool output' do
      output = {
        kind: 'image',
        data_base64: 'base64data',
        mime_type: 'image/png',
        width: 100,
        height: 200
      }
      images = described_class.extract_tool_result_images(output)
      expect(images.length).to eq(1)
      expect(images[0].mime_type).to eq('image/png')
      expect(images[0].data_base64).to eq('base64data')
      expect(images[0].width).to eq(100)
      expect(images[0].height).to eq(200)
    end

    it 'extracts images from computer_screenshot output' do
      output = {
        kind: 'computer_screenshot',
        images: [
          { data_base64: 'img1', mime_type: 'image/png' },
          { data_base64: 'img2', mime_type: 'image/jpeg' }
        ]
      }
      images = described_class.extract_tool_result_images(output)
      expect(images.length).to eq(2)
    end

    it 'deduplicates images with same base64' do
      output = {
        kind: 'image',
        data_base64: 'same',
        mime_type: 'image/png',
        images: [{ data_base64: 'same', mime_type: 'image/png' }]
      }
      images = described_class.extract_tool_result_images(output)
      expect(images.length).to eq(1)
    end

    it 'skips entries without mime_type' do
      output = {
        kind: 'image',
        images: [{ data_base64: 'data' }]
      }
      images = described_class.extract_tool_result_images(output)
      expect(images.length).to eq(0)
    end

    it 'skips entries without data_base64' do
      output = {
        kind: 'image',
        images: [{ mime_type: 'image/png' }]
      }
      images = described_class.extract_tool_result_images(output)
      expect(images.length).to eq(0)
    end
  end

  describe '.model_visible_image_output?' do
    it 'returns true for image output with data' do
      output = { kind: 'image', data_base64: 'data', mime_type: 'image/png' }
      expect(described_class.model_visible_image_output?(output)).to be(true)
    end

    it 'returns false for non-image output' do
      output = { kind: 'text', content: 'hello' }
      expect(described_class.model_visible_image_output?(output)).to be(false)
    end

    it 'returns false for nil' do
      expect(described_class.model_visible_image_output?(nil)).to be(false)
    end
  end

  describe '.tool_result_text_without_images' do
    it 'returns string input unchanged' do
      expect(described_class.tool_result_text_without_images('hello')).to eq('hello')
    end

    it 'removes data_base64 from output' do
      output = { kind: 'image', data_base64: 'secret', mime_type: 'image/png' }
      result = described_class.tool_result_text_without_images(output)
      parsed = JSON.parse(result)
      expect(parsed).not_to have_key('data_base64')
      expect(parsed).to have_key('kind')
    end

    it 'removes images array from output' do
      output = { kind: 'computer_screenshot', images: [{ data_base64: 'x' }] }
      result = described_class.tool_result_text_without_images(output)
      parsed = JSON.parse(result)
      expect(parsed).not_to have_key('images')
    end
  end

  describe '.cap_tool_result_images' do
    it 'returns history unchanged when within cap' do
      history = [
        { kind: 'tool_result', output: { kind: 'image', data_base64: 'a', mime_type: 'image/png' } },
        { kind: 'user_message', text: 'hi' }
      ]
      result = described_class.cap_tool_result_images(history, 5)
      expect(result).to eq(history)
    end

    it 'strips old images beyond cap' do
      history = [
        { kind: 'tool_result', output: { kind: 'image', data_base64: 'old', mime_type: 'image/png' } },
        { kind: 'tool_result', output: { kind: 'image', data_base64: 'new', mime_type: 'image/png' } }
      ]
      result = described_class.cap_tool_result_images(history, 1)
      expect(result[0][:output][:data_base64]).to include('omitted')
      expect(result[1][:output][:data_base64]).to eq('new')
    end

    it 'returns history when cap is 0 and no images' do
      history = [{ kind: 'user_message', text: 'hi' }]
      result = described_class.cap_tool_result_images(history, 0)
      expect(result).to eq(history)
    end
  end

  describe '.to_image' do
    it 'creates ToolResultImage from hash' do
      value = { data_base64: 'data', mime_type: 'image/png', width: 100, height: 200 }
      image = described_class.send(:to_image, value)
      expect(image).to be_a(DeepForge::Loop::ToolResultImage::ToolResultImage)
      expect(image.mime_type).to eq('image/png')
      expect(image.data_base64).to eq('data')
    end

    it 'returns nil for empty data_base64' do
      value = { data_base64: '', mime_type: 'image/png' }
      expect(described_class.send(:to_image, value)).to be_nil
    end

    it 'returns nil for empty mime_type' do
      value = { data_base64: 'data', mime_type: '' }
      expect(described_class.send(:to_image, value)).to be_nil
    end

    it 'returns nil for non-hash' do
      expect(described_class.send(:to_image, 'string')).to be_nil
    end
  end
end
