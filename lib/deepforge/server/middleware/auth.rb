# frozen_string_literal: true

# 文件用途：认证模块，提供 HTTP 请求的 Bearer Token 认证功能
# 使用方法：通过 DeepForge::Server.bearer_token 和 DeepForge::Server.authorized? 方法进行认证

module DeepForge
  module Server
    # 从 Authorization 头部提取 Bearer Token
    # @param headers [Hash] 请求头
    # @return [String, nil] Bearer Token 或 nil
    def self.bearer_token(headers)
      header = headers['authorization']
      return nil unless header

      match = header.match(/^Bearer\s+(.+)$/i)
      match&.[](1)
    end

    # 检查请求是否使用预期的 Token 进行了授权
    # @param headers [Hash] 请求头
    # @param expected_token [String] 预期的 Bearer Token
    # @param insecure [Boolean] 是否跳过认证检查（用于本地开发）
    # @return [Boolean] 如果已授权返回 true
    def self.authorized?(headers, expected_token, insecure = false)
      return true if insecure

      expected_token.length.positive? && bearer_token(headers) == expected_token
    end
  end
end
