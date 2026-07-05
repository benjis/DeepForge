# frozen_string_literal: true

# 文件用途：定义附件相关的请求、响应和元数据数据结构
# 使用方法：用于附件的上传、存储和文本回退处理

module DeepForge
  module Contracts
    # 附件文本回退结构：当图片无法直接发送给模型时，存储 Base64 编码的图片数据及元信息
    AttachmentTextFallback = Struct.new(
      :data_base64,
      :mime_type,
      :byte_size,
      :width,
      :height,
      :was_compressed,
      keyword_init: true
    )

    # 附件元数据：存储附件的完整元信息，包括ID、名称、MIME类型、大小等
    AttachmentMetadata = Struct.new(
      :id,
      :name,
      :mime_type,
      :byte_size,
      :hash,
      :width,
      :height,
      :text_fallback,
      :thread_ids,
      :workspaces,
      :created_at,
      :updated_at,
      keyword_init: true
    )

    # 附件上传请求：客户端提交附件时使用，包含文件名、MIME类型和 Base64 数据
    AttachmentUploadRequest = Struct.new(
      :name,
      :mime_type,
      :data_base64,
      :text_fallback,
      :thread_id,
      :workspace,
      keyword_init: true
    )

    # 附件上传响应：服务端返回上传结果，包含附件元数据
    AttachmentUploadResponse = Struct.new(
      :attachment,
      keyword_init: true
    )

    # 附件诊断信息：用于调试，返回附件存储的统计信息
    AttachmentDiagnostics = Struct.new(
      :enabled,
      :root_dir,
      :count,
      :total_bytes,
      keyword_init: true
    )
  end
end
