# frozen_string_literal: true

# 文件用途：工具主机端口，提供工具调用执行和管理功能
# 使用方法：继承ToolHost类并实现list_tools和execute方法，支持本地和远程工具执行

module DeepForge
  module Ports
    # 模块功能：工具提供者类型常量定义
    # 使用方法：使用这些常量标识不同类型的工具提供者
    module ToolProviderKind
      BUILT_IN = 'built-in'
      MCP = 'mcp'
      WEB = 'web'
      SKILL = 'skill'
      MEMORY = 'memory'
      GUI = 'gui'
      DELEGATION = 'delegation'
    end

    # 结构体功能：工具提供者策略数据结构
    # 使用方法：包含ID、类型、启用状态、可用性和原因信息
    ToolProviderPolicy = Struct.new(
      :id,
      :kind,
      :enabled,
      :available,
      :reason,
      keyword_init: true
    )

    # 结构体功能：GUI计划上下文数据结构
    # 使用方法：可选的GUI计划上下文，在开始草稿或优化计划轮次时由渲染器提供
    GuiPlanContext = Struct.new(
      :operation,
      :workspace_root,
      :relative_path,
      :plan_id,
      :source_request,
      :title,
      :turn_id,
      keyword_init: true
    )

    # 结构体功能：工具主机上下文数据结构
    # 使用方法：包含工具执行所需的所有上下文信息，如线程ID、工作区、模型等
    ToolHostContext = Struct.new(
      :thread_id,
      :turn_id,
      :workspace,
      :thread_mode,
      :gui_plan,
      :model,
      :active_skill_ids,
      :memory_policy,
      :delegation_policy,
      :allowed_provider_ids,
      :allowed_tool_names,
      :approval_policy,
      :abort_signal,
      :await_approval,
      :await_user_input,
      keyword_init: true
    )

    # 结构体功能：工具调用相似结构数据
    # 使用方法：包含调用ID、工具名称、提供者ID、工具类型和参数
    ToolCallLike = Struct.new(
      :call_id,
      :tool_name,
      :provider_id,
      :tool_kind,
      :arguments,
      keyword_init: true
    )

    # 结构体功能：工具执行更新数据结构
    # 使用方法：包含执行输出和错误标志
    ToolExecutionUpdate = Struct.new(
      :output,
      :is_error,
      keyword_init: true
    )

    # 结构体功能：工具主机执行结果数据结构
    # 使用方法：包含执行产生的项和审批状态
    ToolHostResult = Struct.new(
      :item,
      :approved,
      keyword_init: true
    )

    # @abstract Subclass and implement {#list_tools} and {#execute}
    # Port for executing tool calls. The local tool host uses approval
    # boundaries and abort-signal cancellation; a remote host can fan out
    # to a sandboxed environment. The loop and tests only see the port.

    # 类功能：工具主机端口基类，定义工具执行接口
    class ToolHost
      # 属性功能：获取工具主机ID
      # @return [String]
      attr_reader :id

      # 方法功能：初始化工具主机
      # 参数：id - 工具主机唯一标识符
      # 使用方法：传入ID创建工具主机实例
      # @param id [String]
      def initialize(id:)
        @id = id
      end

      # 方法功能：列出当前轮次可用的工具
      # 参数：context - 可选的工具主机上下文
      # 返回值：工具规格数组
      # 使用方法：传入可选上下文，返回可用工具列表
      # @param context [ToolHostContext, nil]
      # @return [Array<Hash>]
      def list_tools(context: nil)
        raise NotImplementedError
      end

      # 方法功能：执行工具调用
      # 参数：call - 工具调用对象，context - 工具主机上下文，on_update - 可选更新回调
      # 返回值：工具执行结果对象
      # 使用方法：传入调用、上下文和可选更新回调
      # @param call [ToolCallLike]
      # @param context [ToolHostContext]
      # @param on_update [Proc, nil]
      # @return [ToolHostResult]
      def execute(call, context, on_update: nil)
        raise NotImplementedError
      end

      # 方法功能：清理读取跟踪器（可选运行时清理钩子）
      # 参数：thread_id - 可选的线程ID
      # 使用方法：传入可选线程ID，清理读取跟踪状态
      # @param thread_id [String, nil]
      def clear_read_tracker(thread_id: nil)
        # Optional override
      end
    end
  end
end
