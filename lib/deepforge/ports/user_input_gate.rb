# frozen_string_literal: true

# 文件用途：用户输入网关端口，提供与用户交互的功能
# 使用方法：继承UserInputGate类并实现所有方法，处理用户输入请求和响应

module DeepForge
  module Ports
    # 结构体功能：用户输入答案数据结构
    # 使用方法：包含答案ID、标签和值
    UserInputAnswer = Struct.new(
      :id,
      :label,
      :value,
      keyword_init: true
    )

    # 结构体功能：用户输入选项数据结构
    # 使用方法：包含选项标签和描述
    UserInputOption = Struct.new(
      :label,
      :description,
      keyword_init: true
    )

    # 结构体功能：用户输入问题数据结构
    # 使用方法：包含问题头部、ID、问题内容和选项列表
    UserInputQuestion = Struct.new(
      :header,
      :id,
      :question,
      :options,
      keyword_init: true
    )

    # 结构体功能：用户输入请求数据结构
    # 使用方法：包含请求ID、线程ID、轮次ID、项ID、提示和问题列表
    UserInputRequest = Struct.new(
      :id,
      :thread_id,
      :turn_id,
      :item_id,
      :prompt,
      :questions,
      keyword_init: true
    )

    # @abstract Subclass and implement all methods

    # 类功能：用户输入网关基类，定义用户交互接口
    class UserInputGate
      # 方法功能：提交用户输入请求
      # 参数：input - 用户输入请求对象
      # 返回值：包含状态和答案的哈希
      # 使用方法：传入输入请求，返回提交状态和用户答案
      # @param input [UserInputRequest]
      # @return [Hash] { status: 'submitted'|'cancelled', answers: Array<UserInputAnswer> }
      def request(input)
        raise NotImplementedError
      end

      # 方法功能：获取指定用户输入请求
      # 参数：input_id - 输入请求ID
      # 返回值：用户输入请求对象或nil
      # 使用方法：传入请求ID，返回对应的用户输入请求
      # @param input_id [String]
      # @return [UserInputRequest, nil]
      def get(input_id)
        raise NotImplementedError
      end

      # 方法功能：解决用户输入请求
      # 参数：input_id - 输入请求ID，resolution - 解决结果哈希
      # 返回值：布尔值表示操作是否成功
      # 使用方法：传入请求ID和解决结果，解决用户输入
      # @param input_id [String]
      # @param resolution [Hash]
      # @return [Boolean]
      def resolve(input_id, resolution)
        raise NotImplementedError
      end

      # 方法功能：获取待处理的用户输入请求
      # 参数：thread_id - 可选的线程ID用于过滤
      # 返回值：用户输入请求数组
      # 使用方法：传入可选线程ID过滤，返回待处理请求列表
      # @param thread_id [String, nil]
      # @return [Array<UserInputRequest>]
      def pending(thread_id: nil)
        raise NotImplementedError
      end

      # 方法功能：重置用户输入网关状态
      # 使用方法：调用清空所有待处理请求
      def reset
        raise NotImplementedError
      end
    end
  end
end
