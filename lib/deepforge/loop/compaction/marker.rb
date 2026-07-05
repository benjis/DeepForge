# frozen_string_literal: true

# 文件用途：压缩标记工具，用于历史折叠时生成和管理摘要标记
# 使用方法：通过 CompactionMarker 模块的类方法调用

require 'digest'
require 'json'

# 模块功能：压缩标记工具
# 提供 SHA256 哈希计算、摘要标记创建、条目摘要生成等功能
module DeepForge
  module Loop
    module CompactionMarker
      module_function

      # 计算内容的截断 SHA256 哈希值
      # @param content [String, Array<Byte>] 待哈希的内容
      # @param length [Integer] 哈希截取长度
      # @return [String] 截断的 SHA256 哈希值
      def compute_short_hash(content, length = 16)
        Digest::SHA256.hexdigest(content.to_s)[0, length]
      end

      # 创建工具摘要标记
      # @param short_hash [String] 要包含在标记中的哈希值
      # @return [String] 摘要标记字符串
      def create_tool_digest_marker(short_hash)
        "<deepforge:tool_digest sha256=\"#{escape_marker_attribute(short_hash)}\">"
      end

      # 生成压缩条目的摘要源数据
      # @param items [Array<Hash>] 待摘要的条目
      # @return [String] 稳定的 JSON 字符串
      def compacted_items_digest_source(items)
        stable_stringify(items.map { |item| compaction_digest_shape(item) })
      end

      # 将轮次条目转换为摘要形状（用于哈希计算）
      # @param item [Hash] 轮次条目
      # @return [Hash, nil] 摘要形状
      def compaction_digest_shape(item)
        case item[:kind]
        when 'user_message'
          { kind: item[:kind], text: item[:text] }
        when 'assistant_text'
          { kind: item[:kind], text: item[:text] }
        when 'assistant_reasoning'
          { kind: item[:kind], text: item[:text] }
        when 'tool_call'
          {
            kind: item[:kind],
            call_id: item[:call_id] || item[:callId],
            tool_name: item[:tool_name] || item[:toolName],
            arguments: stable_shape(item[:arguments]),
            summary: item[:summary]
          }
        when 'tool_result'
          {
            kind: item[:kind],
            call_id: item[:call_id] || item[:callId],
            tool_name: item[:tool_name] || item[:toolName],
            output: stable_shape(item[:output]),
            is_error: item[:is_error] || item[:isError]
          }
        when 'approval'
          {
            kind: item[:kind],
            approval_id: item[:approval_id] || item[:approvalId],
            tool_name: item[:tool_name] || item[:toolName],
            summary: item[:summary],
            status: item[:status]
          }
        when 'user_input'
          {
            kind: item[:kind],
            input_id: item[:input_id] || item[:inputId],
            prompt: item[:prompt],
            status: item[:status]
          }
        when 'compaction'
          {
            kind: item[:kind],
            summary: item[:summary],
            source_digest: item[:source_digest] || item[:sourceDigest],
            digest_marker: item[:digest_marker] || item[:digestMarker],
            source_item_ids: item[:source_item_ids] || item[:sourceItemIds],
            replaced_tokens: item[:replaced_tokens] || item[:replacedTokens]
          }
        when 'error'
          {
            kind: item[:kind],
            message: item[:message],
            code: item[:code]
          }
        end
      end

      # 将值转换为稳定的形状（键排序的哈希）
      # @param value [Object] 待转换的值
      # @return [Object] 键排序后的稳定形状
      def stable_shape(value)
        case value
        when Array
          value.map { |v| stable_shape(v) }
        when Hash
          value.each_with_object({}) { |(k, v), out| out[k] = stable_shape(v) }
               .sort.to_h
        else
          value
        end
      end

      # 将值稳定地序列化为 JSON 字符串
      # @param value [Object] 待序列化的值
      # @return [String] 稳定的 JSON 字符串
      def stable_stringify(value)
        JSON.generate(stable_shape(value))
      end

      # 转义标记属性值中的特殊字符
      # @param value [String] 待转义的属性值
      # @return [String] 转义后的属性值
      def escape_marker_attribute(value)
        value.gsub('&', '&amp;').gsub('"', '&quot;')
      end
    end
  end
end
