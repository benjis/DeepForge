# frozen_string_literal: true

# 文件用途：基于内存的用户输入门控器
# 使用方法：当智能体需要向用户请求结构化输入时，通过 request 方法发起输入请求，
#           等待用户通过 HTTP 用户输入路由提交或取消。待处理的请求可通过 ID 访问。

module DeepForge
  module Adapters
    module InMemory
      # 基于内存的用户输入门控器。智能体循环等待 request 方法返回的 future；
      # GUI 通过 HTTP 用户输入路由解析该 future。待处理的请求通过 ID 保持可寻址，
      # 以便重连的渲染器可以提交或取消。
      class UserInputGate
        def initialize
          # 待处理的用户输入请求，键为输入 ID
          @requests = {}
          # 可解析的 future 哈希表，用于等待用户输入结果
          @resolvers = {}
        end

        # 发起一个用户输入请求，返回可等待的 future 对象
        # 参数：input - 输入请求哈希，必须包含 :id 和 :thread_id 键
        # 返回值：Concurrent::Promises::ResolvableFuture，可通过 fulfill 获取用户输入
        def request(input)
          @requests[input[:id]] = input

          future = Concurrent::Promises.resolvable_future
          @resolvers[input[:id]] = future
          future
        end

        # 根据 ID 获取指定的用户输入请求
        # 参数：input_id - 输入请求 ID
        # 返回值：Hash 或 nil，用户输入请求详情
        def get(input_id)
          @requests[input_id]
        end

        # 解析用户输入请求，从待处理列表中移除并释放 future
        # 参数：input_id - 输入请求 ID，resolution - 解析结果哈希
        # 返回值：Boolean，是否成功解析
        def resolve(input_id, resolution)
          request = @requests.delete(input_id)
          return false unless request

          resolver = @resolvers.delete(input_id)
          resolver&.fulfill(resolution)

          true
        end

        # 获取待处理的用户输入请求列表
        # 参数：thread_id - 线程 ID（可选），为 nil 时返回所有待处理请求
        # 返回值：Array<Hash>，待处理的用户输入请求数组
        def pending(thread_id = nil)
          @requests.values.select do |r|
            thread_id.nil? || r[:thread_id] == thread_id
          end
        end

        # 重置用户输入门控器，拒绝所有待处理的请求并清空状态
        # 返回值：void
        def reset
          @resolvers.each_value do |resolver|
            resolver.reject(RuntimeError.new('user input gate reset'))
          end

          @requests.clear
          @resolvers.clear
        end
      end
    end
  end
end
