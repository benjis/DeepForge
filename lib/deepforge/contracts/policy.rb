# frozen_string_literal: true

# 文件用途：定义审批策略和沙箱模式的常量
# 使用方法：用于配置代理的审批行为和文件系统访问权限

module DeepForge
  module Contracts
    # 审批策略常量：定义工具调用的审批模式
    module ApprovalPolicy
      ON_REQUEST = 'on-request'
      UNTRUSTED = 'untrusted'
      NEVER = 'never'
      AUTO = 'auto'
      SUGGEST = 'suggest'
    end

    # 默认审批策略：按需审批（on-request）
    DEFAULT_APPROVAL_POLICY = ApprovalPolicy::ON_REQUEST

    # 沙箱模式常量：定义代理的文件系统访问权限级别
    module SandboxMode
      READ_ONLY = 'read-only'
      WORKSPACE_WRITE = 'workspace-write'
      DANGER_FULL_ACCESS = 'danger-full-access'
      EXTERNAL_SANDBOX = 'external-sandbox'
    end

    # 默认沙箱模式：工作空间写入（workspace-write）
    DEFAULT_SANDBOX_MODE = SandboxMode::WORKSPACE_WRITE
  end
end
