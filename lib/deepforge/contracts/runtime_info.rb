# frozen_string_literal: true

# 文件用途：定义运行时信息响应的数据结构
# 使用方法：用于返回运行时的配置、状态和能力信息

module DeepForge
  module Contracts
    # 运行时信息响应：包含主机、端口、配置路径、模型、策略等运行时信息
    RuntimeInfoResponse = Struct.new(
      :host,
      :port,
      :data_dir,
      :config_path,
      :model,
      :approval_policy,
      :sandbox_mode,
      :token_economy_mode,
      :insecure,
      :started_at,
      :pid,
      :capabilities,
      keyword_init: true
    )
  end
end
