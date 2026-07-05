# frozen_string_literal: true

# 文件用途：内容搜索工具的便捷入口模块
# 使用方法：通过 Tool.create_grep_tool 创建内容搜索工具实例

require_relative 'builtin_search_tools'

module DeepForge
  module Adapters
    module Tool
      # Grep 操作结构体，包含 search 函数
      GrepOperations = Struct.new(:search, keyword_init: true)
      # 别名：从 BuiltinSearchTools 导出的 Grep 工具选项结构体
      GrepToolOptions = DeepForge::Adapters::Tool::BuiltinSearchTools::GrepLocalToolOptions

      # 方法功能：创建内容搜索工具定义
      # 参数：options - Grep 工具选项（可选）
      # 返回值：包含工具定义的哈希
      def self.create_grep_tool(options = {})
        DeepForge::Adapters::Tool::BuiltinSearchTools.create_grep_tool(options)
      end

      # 方法功能：创建内容搜索工具定义（别名方法）
      # 参数：options - Grep 工具选项（可选）
      # 返回值：同 create_grep_tool
      def self.create_grep_tool_definition(options = {})
        create_grep_tool(options)
      end

      # 方法功能：获取默认的本地搜索操作
      # 返回值：GrepOperations 结构体实例
      def self.default_grep_local_tool_operations
        GrepOperations.new(search: nil)
      end
    end
  end
end
