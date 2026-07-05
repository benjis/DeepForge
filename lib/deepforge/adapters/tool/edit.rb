# frozen_string_literal: true

# 文件用途：编辑工具的便捷入口模块
# 使用方法：通过 Tool.create_edit_tool 创建编辑工具实例

require_relative 'builtin_file_tools'

module DeepForge
  module Adapters
    module Tool
      # 别名：从 BuiltinFileTools 导出的编辑操作结构体
      EditOperations = DeepForge::Adapters::Tool::BuiltinFileTools::EditLocalToolOperations
      # 别名：从 BuiltinFileTools 导出的编辑工具选项结构体
      EditToolOptions = DeepForge::Adapters::Tool::BuiltinFileTools::EditLocalToolOptions

      # 方法功能：创建编辑工具定义
      # 参数：options - 编辑工具选项（可选）
      # 返回值：包含工具定义的哈希
      def self.create_edit_tool(options = {})
        DeepForge::Adapters::Tool::BuiltinFileTools.create_edit_tool(options)
      end

      # 方法功能：创建编辑工具定义（别名方法）
      # 参数：options - 编辑工具选项（可选）
      # 返回值：同 create_edit_tool
      def self.create_edit_tool_definition(options = {})
        create_edit_tool(options)
      end

      # 方法功能：获取默认的本地编辑操作
      # 返回值：EditLocalToolOperations 结构体实例
      def self.default_edit_local_tool_operations
        DeepForge::Adapters::Tool::BuiltinFileTools.default_edit_operations
      end
    end
  end
end
