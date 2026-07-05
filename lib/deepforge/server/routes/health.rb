# frozen_string_literal: true

# 文件用途：健康检查路由模块，提供服务状态检查端点
# 使用方法：通过 GET /health 端点检查服务是否正常运行（无需认证）

require_relative '../response'

module DeepForge
  module Server
    module Routes
      # 构建健康检查响应。该端点无需认证。
      # @return [JsonResponse] 健康检查响应
      def self.health_json_response
        DeepForge::Server.json_response({ status: 'ok', service: 'deepforge', mode: 'serve' })
      end
    end
  end
end
