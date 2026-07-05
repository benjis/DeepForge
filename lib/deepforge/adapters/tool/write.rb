# frozen_string_literal: true

# 文件用途：文件写入工具的便捷入口模块
# 使用方法：通过 Tool.create_write_tool 创建文件写入工具实例

require_relative 'builtin_file_tools'

module DeepForge
  module Adapters
    module Tool
      # 别名：从 BuiltinFileTools 导出的写入操作结构体
      WriteOperations = DeepForge::Adapters::Tool::BuiltinFileTools::WriteLocalToolOperations
      # 别名：从 BuiltinFileTools 导出的写入工具选项结构体
      WriteToolOptions = DeepForge::Adapters::Tool::BuiltinFileTools::WriteLocalToolOptions

      # 方法功能：创建文件写入工具定义
      # 参数：options - 写入工具选项（可选）
      # 返回值：包含工具定义的哈希
      def self.create_write_tool(options = {})
        DeepForge::Adapters::Tool::BuiltinFileTools.create_write_tool(options)
      end

      # 方法功能：创建文件写入工具定义（别名方法）
      # 参数：options - 写入工具选项（可选）
      # 返回值：同 create_write_tool
      def self.create_write_tool_definition(options = {})
        create_write_tool(options)
      end

      # 方法功能：获取默认的本地写入操作
      # 返回值：WriteLocalToolOperations 结构体实例
      def self.default_write_local_tool_operations
        DeepForge::Adapters::Tool::BuiltinFileTools.default_write_operations
      end
    end
  end
end
