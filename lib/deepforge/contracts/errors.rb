# frozen_string_literal: true

# 文件用途：定义 HTTP/SSE 接口返回的结构化错误码和错误响应
# 使用方法：所有 DeepForge 接口统一使用此模块定义的错误码进行错误响应

module DeepForge
  module Contracts
    # 结构化 API 错误码：所有 HTTP/SSE 端点返回的错误类型
    module DeepForgeErrorCode
      VALIDATION_ERROR = 'validation_error'
      UNAUTHORIZED = 'unauthorized'
      FORBIDDEN = 'forbidden'
      NOT_FOUND = 'not_found'
      CONFLICT = 'conflict'
      RATE_LIMITED = 'rate_limited'
      TURN_IN_PROGRESS = 'turn_in_progress'
      TURN_NOT_RUNNING = 'turn_not_running'
      APPROVAL_NOT_PENDING = 'approval_not_pending'
      CAPABILITY_UNAVAILABLE = 'capability_unavailable'
      PROVIDER_UNAVAILABLE = 'provider_unavailable'
      POLICY_BLOCKED = 'policy_blocked'
      MODEL_MODALITY_UNSUPPORTED = 'model_modality_unsupported'
      ATTACHMENT_VALIDATION_FAILED = 'attachment_validation_failed'
      INTERNAL_ERROR = 'internal_error'
      NOT_IMPLEMENTED = 'not_implemented'
      ABORTED = 'aborted'
    end

    # 错误响应体：包含错误码、消息和详细信息
    ErrorBody = Struct.new(
      :code,
      :message,
      :details,
      keyword_init: true
    )
  end
end
