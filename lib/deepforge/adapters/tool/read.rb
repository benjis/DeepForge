# frozen_string_literal: true

# 文件用途：文件读取工具的便捷入口模块
# 使用方法：通过 Tool.create_read_tool 创建文件读取工具实例

require_relative 'builtin_read_tool'

module DeepForge
  module Adapters
    module Tool
      # 别名：从 BuiltinReadTool 导出的读取操作结构体
      ReadOperations = DeepForge::Adapters::Tool::BuiltinReadTool::ReadOperations
      # 别名：从 BuiltinReadTool 导出的读取工具选项结构体
      ReadToolOptions = DeepForge::Adapters::Tool::BuiltinReadTool::ReadToolOptions
      # 别名：从 BuiltinReadTool 导出的缩放图片结果结构体
      ResizedImageResult = DeepForge::Adapters::Tool::BuiltinReadTool::ResizedImageResult
      # 别名：从 BuiltinReadTool 导出的图片缩放选项结构体
      ResizeImageOptions = DeepForge::Adapters::Tool::BuiltinReadTool::ResizeImageOptions

      # 方法功能：创建文件读取工具定义
      # 参数：options - 读取工具选项（可选）
      # 返回值：包含工具定义的哈希
      def self.create_read_tool(options = {})
        DeepForge::Adapters::Tool::BuiltinReadTool.create(options)
      end

      # 方法功能：创建文件读取工具定义（别名方法）
      # 参数：options - 读取工具选项（可选）
      # 返回值：同 create_read_tool
      def self.create_read_tool_definition(options = {})
        create_read_tool(options)
      end

      # 方法功能：获取默认的本地读取操作
      # 返回值：ReadOperations 结构体实例
      def self.default_read_local_tool_operations
        DeepForge::Adapters::Tool::BuiltinReadTool.default_operations
      end
    end
  end
end
