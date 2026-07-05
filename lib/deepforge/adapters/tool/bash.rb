# frozen_string_literal: true

# 文件用途：Bash 工具的便捷入口模块
# 使用方法：通过 Tool.create_bash_tool 或 Tool.create_bash_tool_definition 创建 bash 工具实例

require_relative 'builtin_bash_tool'

module DeepForge
  module Adapters
    module Tool
      # 别名：从 BuiltinBashTool 导出的 Bash 操作结构体
      BashOperations = DeepForge::Adapters::Tool::BuiltinBashTool::BashOperations
      # 别名：从 BuiltinBashTool 导出的 Bash 工具选项结构体
      BashToolOptions = DeepForge::Adapters::Tool::BuiltinBashTool::BashToolOptions

      # 方法功能：创建 Bash 工具定义
      # 参数：options - Bash 工具选项（可选）
      # 返回值：包含工具名称、描述、输入模式和执行逻辑的哈希
      def self.create_bash_tool(options = {})
        DeepForge::Adapters::Tool::BuiltinBashTool.create(options)
      end

      # 方法功能：创建 Bash 工具定义（别名方法）
      # 参数：options - Bash 工具选项（可选）
      # 返回值：同 create_bash_tool
      def self.create_bash_tool_definition(options = {})
        create_bash_tool(options)
      end

      # 方法功能：创建本地 Bash 操作实例
      # 返回值：BashOperations 结构体实例
      def self.create_local_bash_operations
        DeepForge::Adapters::Tool::BuiltinBashTool.create_operations
      end
    end
  end
end
