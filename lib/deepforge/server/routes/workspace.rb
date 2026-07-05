# frozen_string_literal: true

# 文件用途：工作空间路由模块，提供工作空间状态检查功能
# 使用方法：通过 GET /v1/workspace/status 端点获取工作空间状态

require 'json'
require_relative '../response'

module DeepForge
  module Server
    module Routes
      # 构建工作空间状态响应
      # @param inspector [WorkspaceInspector] 工作空间检查器实例
      # @param path [String, nil] 工作空间路径
      # @return [JsonResponse] 工作空间状态
      def self.build_workspace_status_response(inspector:, path:)
        unless path
          return DeepForge::Server.json_response({
                                                   path: '',
                                                   exists: false,
                                                   isGitRepository: false,
                                                   branch: nil,
                                                   headSha: nil,
                                                   isDirty: nil,
                                                   fileChangeCount: nil,
                                                   checkedAt: Time.now.utc.strftime('%FT%TZ')
                                                 })
        end

        status = inspector.status(path)
        DeepForge::Server.json_response(status)
      end
    end
  end
end
