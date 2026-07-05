# frozen_string_literal: true

# 文件用途：工具结果图像处理模块，管理工具返回的图像在模型中的路由
# 使用方法：通过 DeepForge::Loop::ToolResultImage 模块的类方法调用
# 三个流水线层在图像到达模型前剥离或限制 data_base64

require 'json'

module DeepForge
  module Loop
    # 模块功能：工具结果图像路由辅助工具
    # 管理工具返回的图像（如 read 工具读取图片、computer_use 返回截图）
    # 在模型中的路由，支持图像提取、文本序列化和图像上限控制
    module ToolResultImage
      # 工具结果图像的数据结构
      # @!attribute mime_type
      #   @return [String] 图像的 MIME 类型
      # @!attribute data_base64
      #   @return [String] base64 编码的图像数据
      # @!attribute width
      #   @return [Integer, nil] 图像宽度（像素）
      # @!attribute height
      #   @return [Integer, nil] 图像高度（像素）
      ToolResultImage = Struct.new(:mime_type, :data_base64, :width, :height, keyword_init: true)

      # 每张图像的固定 token 估算值，用于 token 估算器和请求卫生预算
      IMAGE_TOOL_RESULT_TOKEN_ESTIMATE = 1_200

      # 转发到视觉模型的工具输出 kind 值
      # `image` 是 read 工具；`computer_screenshot` 是 computer_use
      MODEL_VISIBLE_IMAGE_KINDS = Set.new(%w[image computer_screenshot]).freeze

      # 被淘汰图像的占位文本
      EVICTED_IMAGE_PLACEHOLDER =
        '[older screenshot omitted to save context; take another screenshot if you need the current view]'

      # 从工具结果输出中提取所有模型可见的图像
      #
      # 支持 read 工具形状（顶层 `data_base64`/`mime_type`）和
      # computer_use 形状（`images` 数组）。对于非识别图像类型
      # 或不携带 base64 负载的输出返回 `[]`。
      #
      # @param output [Object] 工具结果输出
      # @return [Array<ToolResultImage>] 提取的图像列表
      def self.extract_tool_result_images(output)
        return [] unless is_record?(output)

        kind = output[:kind] || output['kind'] || ''
        return [] unless MODEL_VISIBLE_IMAGE_KINDS.include?(kind)

        images = []

        if output[:images].is_a?(Array)
          output[:images].each do |entry|
            image = to_image(entry)
            images << image if image
          end
        end

        single = to_image(output)
        images << single if single && images.none? { |image| image.data_base64 == single.data_base64 }

        images
      end

      # 检查输出是否应作为图像转发给模型
      #
      # @param output [Object] 工具结果输出
      # @return [Boolean] 当输出包含模型可见图像时返回 true
      def self.model_visible_image_output?(output)
        extract_tool_result_images(output).length.positive?
      end

      # 将工具结果输出序列化为不含 base64 负载的文本
      #
      # 大型 base64 负载作为真实图像部分传输
      #
      # @param output [Object] 工具结果输出
      # @return [String] 不含图像的文本表示
      def self.tool_result_text_without_images(output)
        return output if output.is_a?(String)
        return output.to_s unless is_record?(output)

        clone = {}
        output.each do |key, value|
          next if ['data_base64', :data_base64].include?(key)
          next if ['images', :images].include?(key)

          clone[key] = value
        end

        JSON.generate(clone)
      rescue StandardError
        ''
      end

      # 仅在发送历史中最近的 `max_kept` 个图像工具结果上保留内联图像负载
      #
      # 旧截图被折叠为小文本注释。这限制了长 computer-use 会话的
      # 上下文增长，并保持下游卫生/经济层的低成本。操作在副本上——
      # 持久化的会话日志不受影响。
      #
      # @param history [Array<TurnItem>] 对话历史
      # @param max_kept [Integer] 保留内联的最大图像数
      # @return [Array<TurnItem] 剥离旧图像后的历史
      def self.cap_tool_result_images(history, max_kept)
        keep = [0, max_kept.to_i].max

        image_indexes = []
        history.each_with_index do |item, index|
          image_indexes << index if item[:kind] == 'tool_result' && model_visible_image_output?(item[:output])
        end

        return history if image_indexes.length <= keep

        evict = image_indexes[0...(image_indexes.length - keep)].to_set

        history.map.with_index do |item, index|
          if evict.include?(index) && item[:kind] == 'tool_result'
            { **item, output: strip_images_from_output(item[:output]) }
          else
            item
          end
        end
      end

      # 从类哈希值中提取 ToolResultImage（内部方法）
      #
      # @param value [Object] 待提取图像的值
      # @return [ToolResultImage, nil] 提取的图像或 nil
      # @api private
      def self.to_image(value)
        return nil unless is_record?(value)

        data_base64 = value[:data_base64] || value['data_base64'] || ''
        mime_type = value[:mime_type] || value['mime_type'] || ''
        return nil if data_base64.empty? || mime_type.empty?

        width = value[:width] || value['width']
        height = value[:height] || value['height']

        ToolResultImage.new(
          mime_type: mime_type,
          data_base64: data_base64,
          width: width.is_a?(Integer) ? width : nil,
          height: height.is_a?(Integer) ? height : nil
        )
      end
      private_class_method :to_image

      # 从输出中剥离图像，替换为占位文本（内部方法）
      #
      # @param output [Object] 工具结果输出
      # @return [Object] 替换图像后的输出
      # @api private
      def self.strip_images_from_output(output)
        return output unless is_record?(output)

        clone = {}
        output.each do |key, value|
          if ['data_base64', :data_base64].include?(key)
            clone[key] = EVICTED_IMAGE_PLACEHOLDER
            next
          end

          if ['images', :images].include?(key)
            clone[:images_omitted] = value.is_a?(Array) ? value.length : 1
            next
          end

          clone[key] = value
        end

        clone[:note] = EVICTED_IMAGE_PLACEHOLDER unless clone[:note].is_a?(String)
        clone
      end
      private_class_method :strip_images_from_output

      # 检查值是否为记录（类哈希对象）（内部方法）
      #
      # @param value [Object] 待检查的值
      # @return [Boolean] 如果值是类哈希对象则返回 true
      # @api private
      def self.is_record?(value)
        value.is_a?(Hash)
      end
      private_class_method :is_record?
    end
  end
end
