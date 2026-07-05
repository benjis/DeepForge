# frozen_string_literal: true

# 文件用途：工具能力注册表
# 使用方法：管理工具提供者及其工具的注册、查询和解析

module DeepForge
  module Adapters
    module Tool
      # 工具记录结构体，包含提供者策略和工具定义
      CapabilityToolRecord = Struct.new(:provider, :tool, keyword_init: true)

      # 工具提供者结构体，包含 ID、类型、启用状态和工具列表
      CapabilityToolProvider = Struct.new(:id, :kind, :enabled, :available, :reason, :tools, keyword_init: true)

      # 工具规范结构体，list_tools 方法返回的工具描述
      CapabilityToolSpec = Struct.new(
        :name, :description, :input_schema, :tool_kind, :provider_id, :provider_kind,
        keyword_init: true
      )

      # 类功能：工具提供者和工具的注册表，负责管理工具的注册、查询和访问控制
      class CapabilityRegistry
        # 方法功能：从本地工具数组创建注册表
        # 参数：tools - LocalTool 数组
        # 返回值：CapabilityRegistry 实例
        def self.from_local_tools(tools)
          new([
                CapabilityToolProvider.new(
                  id: 'builtin',
                  kind: 'built-in',
                  enabled: true,
                  available: true,
                  tools: tools
                )
              ])
        end

        # @param providers [Array<CapabilityToolProvider>]
        # 方法功能：初始化注册表
        # 参数：providers - 工具提供者数组
        def initialize(providers = [])
          @providers = {}
          @tools = {}
          providers.each { |provider| register_provider(provider) }
        end

        # Register a new tool provider.
        # @param provider [CapabilityToolProvider]
        # @raise [RuntimeError] if provider id is duplicate
        # 方法功能：注册新的工具提供者
        # 参数：provider - CapabilityToolProvider 结构体
        # 异常：如果提供者 ID 重复则抛出异常
        def register_provider(provider)
          raise "duplicate tool provider: #{provider.id}" if @providers.key?(provider.id)

          @providers[provider.id] = provider
          provider.tools.each do |tool|
            raise "duplicate tool name: #{tool.name}" if @tools.key?(tool.name)

            @tools[tool.name] = CapabilityToolRecord.new(
              provider: provider_policy(provider),
              tool: tool
            )
          end
        end

        # List available tools for the given context.
        # @param context [ToolHostContext, nil]
        # @return [Array<CapabilityToolSpec>]
        # 方法功能：列出给定上下文中可用的工具
        # 参数：context - ToolHostContext 可选
        # 返回值：CapabilityToolSpec 数组
        def list_tools(context = nil)
          specs = []
          @tools.each_value do |record|
            next unless can_use_provider?(record.provider, context)
            next unless can_use_tool?(record.tool.name, context)

            next if record.tool.should_advertise && context && !record.tool.should_advertise.call(context)

            specs << CapabilityToolSpec.new(
              name: record.tool.name,
              description: record.tool.description,
              input_schema: record.tool.input_schema,
              tool_kind: record.tool.tool_kind,
              provider_id: record.provider.id,
              provider_kind: record.provider.kind
            )
          end
          specs
        end

        # Resolve a tool by name.
        # @param tool_name [String]
        # @param context [ToolHostContext]
        # @param provider_id [String, nil]
        # @return [CapabilityToolRecord]
        # @raise [RuntimeError] if tool not found or not advertised
        # 方法功能：按名称解析工具
        # 参数：tool_name - 工具名称，context - 上下文，provider_id - 提供者 ID（可选）
        # 返回值：CapabilityToolRecord 结构体
        # 异常：如果工具不存在或未被公布则抛出异常
        def resolve_tool(tool_name, context, provider_id = nil)
          record = @tools[tool_name]
          raise "unknown tool: #{tool_name}" unless record

          if provider_id && provider_id != record.provider.id
            raise "tool #{tool_name} is not provided by #{provider_id}"
          end

          unless can_use_provider?(record.provider, context)
            raise "tool #{tool_name} is not advertised by provider #{record.provider.id}"
          end

          raise "tool #{tool_name} is not advertised by active tool policy" unless can_use_tool?(tool_name, context)

          if record.tool.should_advertise && !record.tool.should_advertise.call(context)
            raise "tool #{tool_name} is not advertised in this turn context"
          end

          record
        end

        # Return diagnostics about all providers.
        # @return [Array<ToolProviderPolicy>]
        # 方法功能：返回所有提供者的诊断信息
        # 返回值：ToolProviderPolicy 数组
        def diagnostics
          @providers.values.map { |provider| provider_policy(provider) }
        end

        private

        # @return [Boolean]
        # 方法功能：检查是否可以使用指定的提供者
        # 参数：provider - 工具提供者，context - 上下文（可选）
        # 返回值：布尔值
        def can_use_provider?(provider, context = nil)
          return false unless provider.enabled && provider.available

          allowed = context&.allowed_provider_ids
          return false if allowed && !allowed.include?(provider.id)

          true
        end

        # @return [Boolean]
        # 方法功能：检查是否可以使用指定的工具
        # 参数：tool_name - 工具名称，context - 上下文（可选）
        # 返回值：布尔值
        def can_use_tool?(tool_name, context = nil)
          allowed = context&.allowed_tool_names
          return !allowed || allowed.include?(tool_name)

          true
        end

        # Extract policy fields from a provider.
        # @param provider [CapabilityToolProvider]
        # @return [Hash]
        # 方法功能：从提供者中提取策略字段
        # 参数：provider - CapabilityToolProvider 结构体
        # 返回值：策略哈希
        def provider_policy(provider)
          {
            id: provider.id,
            kind: provider.kind,
            enabled: provider.enabled,
            available: provider.available,
            reason: provider.reason
          }.compact
        end
      end
    end
  end
end
