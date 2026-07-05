# frozen_string_literal: true

# 文件用途：基于内存的工具调用审批门控器
# 使用方法：当智能体需要执行需要用户审批的工具调用时，通过 request 方法发起审批请求，
#           等待用户通过 decide 方法做出允许或拒绝的决定。适用于测试和默认运行时环境。

module DeepForge
  module Adapters
    module InMemory
      # 基于内存的审批门控器。HTTP 层通过 decide 方法提交审批决定；
      # 智能体循环通过 await request promise 来获知用户是否允许或拒绝调用。
      class ApprovalGate
        def initialize
          # 已注册的审批请求，键为审批 ID
          @approvals = {}
          # 可解析的 future 哈希表，用于等待审批结果
          @resolvers = {}
        end

        # 发起一个审批请求，返回可等待的 future 对象
        # 参数：approval - 审批请求哈希，必须包含 :id 键
        # 返回值：Concurrent::Promises::ResolvableFuture，可通过 fulfill 获取审批结果
        def request(approval)
          @approvals[approval[:id]] = approval

          future = Concurrent::Promises.resolvable_future
          @resolvers[approval[:id]] = future
          future
        end

        # 对指定的审批请求做出决定（允许或拒绝）
        # 参数：approval_id - 审批请求 ID，decision - 决定（'allow' 或 'deny'），reason - 原因（可选）
        # 返回值：Boolean，是否成功处理了审批决定
        def decide(approval_id, decision, reason = nil)
          approval = @approvals[approval_id]
          return false unless approval

          resolved = resolve_approval_request(approval, decision, reason)
          @approvals[approval_id] = resolved

          resolver = @resolvers.delete(approval_id)
          resolver&.fulfill(decision)

          true
        end

        # 获取待处理的审批请求列表
        # 参数：thread_id - 线程 ID（可选），为 nil 时返回所有待处理请求
        # 返回值：Array<Hash>，待处理的审批请求数组
        def pending(thread_id = nil)
          @approvals.values.select do |a|
            a[:status] == 'pending' && (thread_id.nil? || a[:thread_id] == thread_id)
          end
        end

        # 根据 ID 获取指定的审批请求详情
        # 参数：approval_id - 审批请求 ID
        # 返回值：Hash 或 nil，审批请求详情
        def get(approval_id)
          @approvals[approval_id]
        end

        # 解析审批请求（测试用），模拟外部决策并释放 promise
        # 参数：approval_id - 审批请求 ID，decision - 决定，reason - 原因（可选）
        # 返回值：Boolean，是否成功解析
        def resolve(approval_id, decision, reason = nil)
          decide(approval_id, decision, reason)
        end

        private

        # 将审批请求解析为最终状态（内部方法）
        # 参数：approval - 原始审批请求，decision - 决定，reason - 原因
        # 返回值：Hash，合并了决策信息的审批请求
        def resolve_approval_request(approval, decision, reason = nil)
          approval.merge(
            status: decision,
            decision: decision,
            reason: reason,
            resolved_at: Time.now.utc.strftime('%FT%TZ')
          )
        end
      end
    end
  end
end
