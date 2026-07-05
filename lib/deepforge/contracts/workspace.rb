# frozen_string_literal: true

# 文件用途：定义工作空间状态的数据结构
# 使用方法：用于返回工作空间的路径、Git 状态和分支信息

module DeepForge
  module Contracts
    # 工作空间状态：返回 GET /v1/workspace/status 的结果
    WorkspaceStatus = Struct.new(
      :path,
      :exists,
      :is_git_repository,
      :branch,
      :head_sha,
      :is_dirty,
      :file_change_count,
      :checked_at,
      keyword_init: true
    )
  end
end
