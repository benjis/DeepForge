# frozen_string_literal: true

# 文件用途：定义审批决策相关的请求和响应数据结构
# 使用方法：用于客户端提交审批决策请求，以及服务端返回审批决策结果

module DeepForge
  module Contracts
    # 审批决策请求：客户端向服务端发送允许/拒绝决策时使用
    ApprovalDecisionRequest = Struct.new(
      :decision,
      :reason,
      keyword_init: true
    )

    # 审批决策响应：服务端返回决策处理结果，包含审批ID和当前状态
    ApprovalDecisionResponse = Struct.new(
      :approval_id,
      :decision,
      :status,
      keyword_init: true
    )
  end
end
