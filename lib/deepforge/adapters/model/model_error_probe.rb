# frozen_string_literal: true

# 文件用途：DeepSeek 端点可达性探测模块
# 使用方法：当 DeepSeek API 返回 5xx 错误时，通过探测请求判断是端点不可达还是服务端错误。
#           提供 host 判断和可达性探测功能。

require 'net/http'
require 'uri'

module DeepForge
  module Adapters
    module Model
      # DeepSeek 端点可达性探测模块。
      module ModelErrorProbe
        module_function

        # 判断给定的 base_url 是否属于 DeepSeek 主机
        # 参数：base_url - API 基础 URL
        # 返回值：Boolean，是否为 DeepSeek 主机
        def deep_seek_host?(base_url)
          uri = URI.parse(base_url)
          host = uri.hostname&.downcase
          host == 'api.deepseek.com' || host&.end_with?('.deepseek.com')
        rescue URI::InvalidURIError
          false
        end

        # 探测 DeepSeek 端点的可达性
        # 参数：base_url - API 基础 URL
        # 返回值：Hash（含 :reachable, :status, :message 键）
        def probe_deep_seek_reachable(base_url:)
          url = probe_url(base_url)

          begin
            uri = URI.parse(url)
            response = Net::HTTP.get_response(uri)

            status = response.code.to_i
            {
              reachable: status < 500,
              status: status,
              message: if status < 500
                         "DeepSeek endpoint is reachable (probe status #{status})."
                       else
                         "DeepSeek endpoint probe also returned #{status}."
                       end
            }
          rescue StandardError => e
            {
              reachable: false,
              message: "DeepSeek endpoint probe failed: #{e.message}"
            }
          end
        end

        # 构建探测用的 URL（自动添加 /v1/models 端点）
        # 参数：base_url - API 基础 URL
        # 返回值：String，完整的探测 URL
        def probe_url(base_url)
          trimmed = base_url.strip.gsub(%r{/+$}, '')
          return 'https://api.deepseek.com/v1/models' if trimmed.empty?

          begin
            uri = URI.parse(trimmed)
            parts = uri.path.split('/').reject(&:empty?)

            last = parts.last&.downcase
            parts.pop if last == 'beta' || last&.match?(/^v\d+$/i)

            uri.path = (parts + %w[v1 models]).join('/')
            uri.query = nil
            uri.to_s
          rescue URI::InvalidURIError
            'https://api.deepseek.com/v1/models'
          end
        end
      end
    end
  end
end
