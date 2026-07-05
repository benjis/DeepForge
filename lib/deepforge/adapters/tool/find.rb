# frozen_string_literal: true

# 文件用途：文件查找工具的便捷入口模块
# 使用方法：通过 Tool.create_find_tool 创建文件查找工具实例

require_relative 'builtin_search_tools'

module DeepForge
  module Adapters
    module Tool
      # Find 操作结构体，包含 glob 函数
      FindOperations = Struct.new(:glob, keyword_init: true)
      # 别名：从 BuiltinSearchTools 导出的 Find 工具选项结构体
      FindToolOptions = DeepForge::Adapters::Tool::BuiltinSearchTools::FindLocalToolOptions

      # 方法功能：创建文件查找工具定义
      # 参数：options - Find 工具选项（可选）
      # 返回值：包含工具定义的哈希
      def self.create_find_tool(options = {})
        DeepForge::Adapters::Tool::BuiltinSearchTools.create_find_tool(options)
      end

      # 方法功能：创建文件查找工具定义（别名方法）
      # 参数：options - Find 工具选项（可选）
      # 返回值：同 create_find_tool
      def self.create_find_tool_definition(options = {})
        create_find_tool(options)
      end

      # 方法功能：获取默认的本地查找操作
      # 返回值：FindOperations 结构体实例
      def self.default_find_local_tool_operations
        FindOperations.new(glob: nil)
      end
    end
  end
end
