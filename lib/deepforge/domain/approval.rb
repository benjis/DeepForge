# frozen_string_literal: true

# 文件用途：定义审批请求的领域模型和工厂方法
# 使用方法：用于创建、解决和过期审批请求

module DeepForge
  module Domain
    # 审批状态常量：定义审批请求的生命周期状态
    module ApprovalStatus
      PENDING = 'pending'
      ALLOWED = 'allowed'
      DENIED = 'denied'
      EXPIRED = 'expired'
    end

    # 审批请求：存储审批请求的完整信息
    ApprovalRequest = Struct.new(
      :id,
      :thread_id,
      :turn_id,
      :tool_name,
      :summary,
      :status,
      :created_at,
      :decided_at,
      :reason,
      keyword_init: true
    )

    # 创建审批请求：初始化一个待处理的审批请求
    # 参数：input - 包含线程ID、轮次ID、工具名称等信息的哈希
    def self.create_approval_request(input)
      ApprovalRequest.new(
        id: input[:id],
        thread_id: input[:thread_id],
        turn_id: input[:turn_id],
        tool_name: input[:tool_name],
        summary: input[:summary],
        status: ApprovalStatus::PENDING,
        created_at: input[:created_at] || Time.now.utc.strftime('%FT%TZ')
      )
    end

    # 解决审批请求：根据决策（允许/拒绝）更新审批状态
    # 参数：request - 待解决的审批请求；decision - "allow" 或 "deny"
    def self.resolve_approval_request(request, decision, reason: nil, decided_at: nil)
      request.dup.tap do |r|
        r.status = decision == 'allow' ? ApprovalStatus::ALLOWED : ApprovalStatus::DENIED
        r.reason = reason
        r.decided_at = decided_at || Time.now.utc.strftime('%FT%TZ')
      end
    end

    # 过期审批请求：将审批请求标记为已过期
    def self.expire_approval_request(request, decided_at: nil)
      request.dup.tap do |r|
        r.status = ApprovalStatus::EXPIRED
        r.decided_at = decided_at || Time.now.utc.strftime('%FT%TZ')
      end
    end
  end
end
