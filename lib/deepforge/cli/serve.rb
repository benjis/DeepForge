# frozen_string_literal: true

#
# 文件用途：DeepForge serve 模式的启动封装模块
# 功能说明：提供 start_deepforge_serve 方法，委托给 Server 模块创建并启动运行时服务
# 使用方法：DeepForge::CLI.start_deepforge_serve(options) 启动 HTTP/SSE 服务

require 'json'
require_relative 'cli_options'
require_relative '../server/runtime'

module DeepForge
  module CLI
    # 方法功能：启动 DeepForge serve 运行时，创建 HTTP 服务句柄
    # 参数：options - ServeOptions 配置对象
    # 返回值：Hash 服务句柄，包含 :runtime、:host、:port、:close 等
    def self.start_deepforge_serve(options)
      DeepForge::Server.start_deepforge_serve(options)
    end
  end
end
