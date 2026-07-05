# frozen_string_literal: true

# 文件用途：运行时信息路由模块，提供服务器运行时信息和诊断数据
# 使用方法：通过 GET /v1/runtime/info 和 /v1/runtime/tools 端点获取运行时信息

require 'json'
require_relative '../response'

module DeepForge
  module Server
    module Routes
      # 构建运行时信息响应
      # @param runtime [ServerRuntime] 运行时实例
      # @return [JsonResponse] 运行时信息
      def self.runtime_info_json_response(runtime)
        DeepForge::Server.json_response(runtime[:info].call)
      end

      # 构建运行时工具诊断响应
      # @param runtime [ServerRuntime] 运行时实例
      # @return [JsonResponse] 工具诊断信息
      def self.runtime_tool_diagnostics_json_response(runtime)
        diagnostics = if runtime[:tool_diagnostics]
                        runtime[:tool_diagnostics].call
                      else
                        {
                          providers: [],
                          mcpServers: [],
                          webProviders: [],
                          skills: {
                            enabled: false,
                            roots: [],
                            skills: [],
                            validationErrors: [],
                            lastActivations: []
                          },
                          attachments: {
                            enabled: false,
                            root_dir: '',
                            count: 0,
                            totalBytes: 0
                          },
                          memory: {
                            enabled: false,
                            root_dir: '',
                            activeCount: 0,
                            tombstoneCount: 0,
                            lastInjectedIds: []
                          }
                        }
                      end

        DeepForge::Server.json_response(redact_secrets(diagnostics))
      end

      # 对诊断数据中的敏感信息进行脱敏处理
      # @param data [Hash] 诊断数据
      # @return [Hash] 脱敏后的诊断数据
      def self.redact_secrets(data)
        return data unless data.is_a?(Hash)

        data.each_with_object({}) do |(key, value), result|
          result[key] = case value
                        when String
                          if key.to_s.match?(/key|token|secret|password/i)
                            value.length > 4 ? "#{value[0..3]}****" : '****'
                          else
                            value
                          end
                        when Hash
                          redact_secrets(value)
                        when Array
                          value.map { |v| v.is_a?(Hash) ? redact_secrets(v) : v }
                        else
                          value
                        end
        end
      end
    end
  end
end
