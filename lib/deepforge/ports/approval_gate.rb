# frozen_string_literal: true

# 文件用途：审批流程端口，用于工具执行时的审批控制
# 使用方法：继承此类并实现所有方法，本地网关是进程内注册表，远程网关可集成外部服务

module DeepForge
  module Ports
    # @abstract Subclass and implement all methods
    # Port for the approval flow used by tool execution. The local gate
    # is the in-process registry; a remote gate could integrate with an
    # external service. The loop awaits a `decide` resolution before
    # proceeding with a tool call.

    # 类功能：审批流程端口基类，定义工具执行审批接口
    class ApprovalGate
      # 方法功能：提交审批请求
      # 参数：approval - 审批请求对象
      # 返回值：'allow' 或 'deny' 字符串
      # 使用方法：传入审批请求，返回审批结果
      # @param approval [Domain::ApprovalRequest]
      # @return [String] 'allow' or 'deny'
      def request(approval)
        raise NotImplementedError
      end

      # 方法功能：做出审批决定
      # 参数：approval_id - 审批ID，decision - 决定('allow'或'deny')，reason - 可选原因
      # 返回值：布尔值表示操作是否成功
      # 使用方法：传入审批ID和决定，可选附加原因
      # @param approval_id [String]
      # @param decision [String] 'allow' or 'deny'
      # @param reason [String, nil]
      # @return [Boolean]
      def decide(approval_id, decision, reason: nil)
        raise NotImplementedError
      end

      # 方法功能：获取待处理的审批请求
      # 参数：thread_id - 可选的线程ID用于过滤
      # 返回值：审批请求数组
      # 使用方法：传入可选线程ID过滤，返回待处理审批列表
      # @param thread_id [String, nil]
      # @return [Array<Domain::ApprovalRequest>]
      def pending(thread_id: nil)
        raise NotImplementedError
      end

      # 方法功能：获取指定审批请求
      # 参数：approval_id - 审批ID
      # 返回值：审批请求对象或nil
      # 使用方法：传入审批ID，返回对应审批请求
      # @param approval_id [String]
      # @return [Domain::ApprovalRequest, nil]
      def get(approval_id)
        raise NotImplementedError
      end
    end
  end
end
