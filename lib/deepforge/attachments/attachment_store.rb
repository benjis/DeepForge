# frozen_string_literal: true

# 文件用途：附件存储管理模块
# 使用方法：提供附件的创建、获取、内容解析和存储管理功能，
#           支持图片附件的验证、存储和权限控制。

require 'digest'
require 'json'
require 'fileutils'
require 'base64'

module DeepForge
  module Attachments
    # 附件内容结构体，包含元数据和二进制数据
    AttachmentContent = Struct.new(:metadata, :data, keyword_init: true)

    # 附件元数据结构体，存储为 JSON 格式
    AttachmentMetadata = Struct.new(
      :id, :name, :mime_type, :byte_size, :hash,
      :width, :height, :text_fallback,
      :thread_ids, :workspaces,
      :created_at, :updated_at,
      keyword_init: true
    )

    # 附件存储接口类
    class AttachmentStore
      # 方法功能：创建新的附件
      # 参数：input - 附件创建参数哈希
      # 返回值：AttachmentMetadata - 创建的附件元数据
      # 异常：ArgumentError - 如果验证失败
      def create(input)
        raise NotImplementedError
      end

      # 方法功能：获取附件元数据
      # 参数：id - 附件 ID
      # 返回值：AttachmentMetadata 或 nil - 附件元数据，未找到返回 nil
      def get(id)
        raise NotImplementedError
      end

      # 方法功能：解析附件内容（带权限验证）
      # 参数：id - 附件 ID
      #       scope - 授权范围哈希
      # 返回值：AttachmentContent - 附件内容对象
      # 异常：RuntimeError - 如果未找到或未授权
      def resolve_content(id, scope)
        raise NotImplementedError
      end

      # 方法功能：获取文本回退策略配置
      # 返回值：Hash - 文本回退策略配置
      def text_fallback_policy
        raise NotImplementedError
      end

      # 方法功能：获取存储附件的诊断信息
      # 返回值：Hash - 包含附件存储状态的诊断数据
      def diagnostics
        raise NotImplementedError
      end
    end

    # 基于文件系统的附件存储实现类
    class FileAttachmentStore < AttachmentStore
      # 方法功能：初始化文件附件存储
      # 参数：root_dir - 附件存储目录
      #       config - 附件能力配置哈希
      #       now_iso - 可选的当前时间函数
      def initialize(root_dir:, config:, now_iso: nil)
        @root_dir = root_dir
        @config = config
        @now_iso = now_iso || -> { Time.now.strftime('%FT%TZ') }
      end

      # 方法功能：创建新的文件附件
      # 参数：input - 附件创建参数哈希
      # 返回值：AttachmentMetadata - 创建的附件元数据
      # 异常：ArgumentError - 如果验证失败
      def create(input)
        FileUtils.mkdir_p(@root_dir)
        image = detect_image(input[:data])
        raise ArgumentError, 'unsupported image MIME type' unless image

        if input[:mime_type] && input[:mime_type] != image[:mime_type]
          raise ArgumentError, 'declared MIME type does not match image content'
        end

        unless @config[:allowed_mime_types].include?(image[:mime_type])
          raise ArgumentError, "image MIME type is not allowed: #{image[:mime_type]}"
        end

        if input[:data].bytesize > @config[:max_image_bytes]
          raise ArgumentError, "image exceeds #{@config[:max_image_bytes]} byte limit"
        end

        max_dimension = [image[:width] || 0, image[:height] || 0].max
        if max_dimension > @config[:max_image_dimension]
          raise ArgumentError, "image exceeds #{@config[:max_image_dimension]}px dimension limit"
        end

        validate_text_fallback(input[:text_fallback], @config) if input[:text_fallback]

        hash = Digest::SHA256.hexdigest(input[:data])
        id = "att_#{hash[0, 24]}"
        content_path = content_path(id)
        metadata_path = metadata_path(id)
        now = @now_iso.call
        existing = get(id)

        if existing
          next_meta = merge_scope(
            existing.to_h.merge(
              input[:text_fallback] ? { text_fallback: input[:text_fallback] } : {},
              updated_at: now
            ).compact,
            input
          )
          ::File.write(content_path, input[:data])
          ::File.write(metadata_path, JSON.pretty_generate(next_meta))
          return AttachmentMetadata.new(**next_meta.transform_keys(&:to_sym))
        end

        metadata_attrs = {
          id: id,
          name: input[:name],
          mime_type: image[:mime_type],
          byte_size: input[:data].bytesize,
          hash: hash,
          thread_ids: [],
          workspaces: [],
          created_at: now,
          updated_at: now
        }
        metadata_attrs[:width] = image[:width] if image[:width]
        metadata_attrs[:height] = image[:height] if image[:height]
        metadata_attrs[:text_fallback] = input[:text_fallback] if input[:text_fallback]
        metadata = merge_scope(metadata_attrs, input)

        ::File.write(content_path, input[:data])
        ::File.write(metadata_path, JSON.pretty_generate(metadata))
        AttachmentMetadata.new(**metadata.transform_keys(&:to_sym))
      end

      # 方法功能：获取文件附件元数据
      # 参数：id - 附件 ID
      # 返回值：AttachmentMetadata 或 nil - 附件元数据，未找到返回 nil
      def get(id)
        raw = ::File.read(metadata_path(id))
        attrs = JSON.parse(raw, symbolize_names: true)
        AttachmentMetadata.new(**attrs)
      rescue StandardError
        nil
      end

      # 方法功能：解析文件附件内容（带权限验证）
      # 参数：id - 附件 ID
      #       scope - 授权范围哈希
      # 返回值：AttachmentContent - 附件内容对象
      # 异常：RuntimeError - 如果未找到或未授权
      def resolve_content(id, scope)
        metadata = get(id)
        raise "attachment not found: #{id}" unless metadata
        raise "attachment is not authorized for this turn: #{id}" unless authorized?(metadata, scope)

        AttachmentContent.new(
          metadata: metadata,
          data: ::File.binread(content_path(id))
        )
      end

      # 方法功能：获取文本回退策略配置
      # 返回值：Hash - 文本回退策略配置
      def text_fallback_policy
        {
          text_fallback_max_base64_bytes: @config[:text_fallback_max_base64_bytes],
          text_fallback_max_image_dimension: @config[:text_fallback_max_image_dimension],
          text_fallback_preferred_mime_type: @config[:text_fallback_preferred_mime_type]
        }
      end

      # 方法功能：获取文件附件存储的诊断信息
      # 返回值：Hash - 包含附件数量、总字节数等诊断数据
      def diagnostics
        FileUtils.mkdir_p(@root_dir)
        entries = begin
          Dir.children(@root_dir).select { |e| e.end_with?('.json') }
        rescue StandardError
          []
        end
        records = entries.filter_map do |entry|
          raw = ::File.read(::File.join(@root_dir, entry))
          attrs = JSON.parse(raw, symbolize_names: true)
          AttachmentMetadata.new(**attrs)
        rescue StandardError
          nil
        end
        {
          enabled: @config[:enabled],
          root_dir: @root_dir,
          count: records.length,
          total_bytes: records.sum(&:byte_size)
        }
      end

      private

      # 方法功能：获取附件内容文件路径
      # 参数：id - 附件 ID
      # 返回值：String - 附件内容文件的完整路径
      def content_path(id)
        ::File.join(@root_dir, "#{id}.bin")
      end

      # 方法功能：获取附件元数据文件路径
      # 参数：id - 附件 ID
      # 返回值：String - 附件元数据文件的完整路径
      def metadata_path(id)
        ::File.join(@root_dir, "#{id}.json")
      end

      # 方法功能：合并附件的授权范围
      # 参数：metadata - 现有元数据哈希
      #       input - 新的输入参数哈希
      # 返回值：Hash - 合并后的元数据哈希
      def merge_scope(metadata, input)
        result = metadata.dup
        result[:thread_ids] = merge_unique(result[:thread_ids] || [], input[:thread_id])
        result[:workspaces] = merge_unique(result[:workspaces] || [], input[:workspace])
        result
      end

      # 方法功能：合并唯一值到数组
      # 参数：values - 现有值数组
      #       value - 新值（可为 nil）
      # 返回值：Array<String> - 合并后的唯一值数组
      def merge_unique(values, value)
        value && !values.include?(value) ? values + [value] : values
      end

      # 方法功能：检查附件是否在授权范围内
      # 参数：metadata - 附件元数据
      #       scope - 授权范围哈希
      # 返回值：Boolean - 如果授权通过返回 true
      def authorized?(metadata, scope)
        return true if (metadata.thread_ids || []).empty? && (metadata.workspaces || []).empty?
        return true if scope[:thread_id] && metadata.thread_ids.include?(scope[:thread_id])
        return true if scope[:workspace] && metadata.workspaces.include?(scope[:workspace])

        false
      end

      # 方法功能：验证文本回退配置
      # 参数：fallback - 文本回退配置哈希
      #       config - 附件能力配置哈希
      # 返回值：void
      # 异常：ArgumentError - 如果验证失败
      def validate_text_fallback(fallback, config)
        unless config[:allowed_mime_types].include?(fallback[:mime_type])
          raise ArgumentError, "fallback image MIME type is not allowed: #{fallback[:mime_type]}"
        end

        if fallback[:data_base64].bytesize > config[:text_fallback_max_base64_bytes]
          raise ArgumentError, "fallback image exceeds #{config[:text_fallback_max_base64_bytes]} base64 byte limit"
        end

        max_dimension = [fallback[:width] || 0, fallback[:height] || 0].max
        return unless max_dimension > config[:text_fallback_max_image_dimension]

        raise ArgumentError, "fallback image exceeds #{config[:text_fallback_max_image_dimension]}px dimension limit"
      end

      # 方法功能：从二进制头部检测图片类型
      # 参数：buffer - 二进制数据缓冲区
      # 返回值：Hash 或 nil - 包含 mime_type、width、height 的哈希，非图片返回 nil
      def detect_image(buffer)
        # PNG
        if buffer.bytesize >= 24 &&
           buffer.bytes[0] == 0x89 && buffer.bytes[1] == 0x50 &&
           buffer.bytes[2] == 0x4e && buffer.bytes[3] == 0x47
          width = buffer[16, 4].unpack1('N')
          height = buffer[20, 4].unpack1('N')
          return { mime_type: 'image/png', width: width, height: height }
        end

        # JPEG
        if buffer.bytesize >= 3 &&
           buffer.bytes[0] == 0xff && buffer.bytes[1] == 0xd8 && buffer.bytes[2] == 0xff
          return { mime_type: 'image/jpeg' }
        end

        # WebP
        if buffer.bytesize >= 12 &&
           buffer[0, 4] == 'RIFF' && buffer[8, 4] == 'WEBP'
          return { mime_type: 'image/webp' }
        end

        nil
      end
    end
  end
end
