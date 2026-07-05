# frozen_string_literal: true

# 文件用途：目录列表工具的便捷入口模块
# 使用方法：通过 Tool.create_ls_tool 创建目录列表工具实例

require_relative 'builtin_search_tools'

module DeepForge
  module Adapters
    module Tool
      # Ls 操作结构体，包含 stat 和 readdir 函数
      LsOperations = Struct.new(:stat, :readdir, keyword_init: true)
      # 别名：从 BuiltinSearchTools 导出的 Ls 工具选项结构体
      LsToolOptions = DeepForge::Adapters::Tool::BuiltinSearchTools::LsLocalToolOptions

      # 方法功能：创建目录列表工具定义
      # 参数：options - Ls 工具选项（可选）
      # 返回值：包含工具定义的哈希
      def self.create_ls_tool(options = {})
        DeepForge::Adapters::Tool::BuiltinSearchTools.create_ls_tool(options)
      end

      # 方法功能：创建目录列表工具定义（别名方法）
      # 参数：options - Ls 工具选项（可选）
      # 返回值：同 create_ls_tool
      def self.create_ls_tool_definition(options = {})
        create_ls_tool(options)
      end

      # 方法功能：获取默认的本地目录列表操作
      # 返回值：LsOperations 结构体实例
      def self.default_ls_local_tool_operations
        LsOperations.new(
          stat: ->(path) { File.stat(path) },
          readdir: ->(path) { Dir.entries(path).map { |name| { name: name } } }
        )
      end
    end
  end
end
