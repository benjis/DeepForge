# frozen_string_literal: true

# 文件用途：模型客户端端口，提供与AI模型提供者通信的接口
# 使用方法：继承ModelClient类并实现stream方法，支持DeepSeek兼容的HTTP客户端或其他适配器

module DeepForge
  module Ports
    # 模块功能：模型响应流式数据块定义
    # 使用方法：提供各种流式数据块的工厂方法，用于驱动助手文本、推理增量、工具调用累积和使用量报告
    module ModelStreamChunk
      # 方法功能：创建助手文本增量数据块
      # 参数：text - 文本增量内容
      # 返回值：包含kind和text的哈希
      # 使用方法：传入文本内容，返回助手文本增量数据块
      # @param text [String]
      # @return [Hash]
      def self.assistant_text_delta(text:)
        { kind: 'assistant_text_delta', text: text }
      end

      # 方法功能：创建助手推理增量数据块
      # 参数：text - 推理文本增量内容
      # 返回值：包含kind和text的哈希
      # 使用方法：传入推理文本，返回助手推理增量数据块
      # @param text [String]
      # @return [Hash]
      def self.assistant_reasoning_delta(text:)
        { kind: 'assistant_reasoning_delta', text: text }
      end

      # 方法功能：创建工具调用增量数据块
      # 参数：call_id - 调用ID，tool_name - 工具名称，arguments_delta - 参数增量
      # 返回值：包含调用信息的哈希
      # 使用方法：传入调用ID和可选的工具名、参数增量
      # @param call_id [String]
      # @param tool_name [String, nil]
      # @param arguments_delta [String, nil]
      # @return [Hash]
      def self.tool_call_delta(call_id:, tool_name: nil, arguments_delta: nil)
        result = { kind: 'tool_call_delta', call_id: call_id }
        result[:tool_name] = tool_name if tool_name
        result[:arguments_delta] = arguments_delta if arguments_delta
        result
      end

      # 方法功能：创建工具调用完成数据块
      # 参数：call_id - 调用ID，tool_name - 工具名称，arguments - 完整参数
      # 返回值：包含完整调用信息的哈希
      # 使用方法：传入调用ID、工具名和完整参数
      # @param call_id [String]
      # @param tool_name [String]
      # @param arguments [Hash]
      # @return [Hash]
      def self.tool_call_complete(call_id:, tool_name:, arguments:)
        { kind: 'tool_call_complete', call_id: call_id, tool_name: tool_name, arguments: arguments }
      end

      # 方法功能：创建使用量数据块
      # 参数：usage - 使用量快照对象
      # 返回值：包含使用量信息的哈希
      # 使用方法：传入使用量快照对象
      # @param usage [Contracts::UsageSnapshot]
      # @return [Hash]
      def self.usage(usage:)
        { kind: 'usage', usage: usage }
      end

      # 方法功能：创建完成数据块
      # 参数：stop_reason - 停止原因，可选值：'stop'、'tool_calls'、'length'或'error'
      # 返回值：包含停止原因的哈希
      # 使用方法：传入停止原因字符串
      # @param stop_reason [String] 'stop', 'tool_calls', 'length', or 'error'
      # @return [Hash]
      def self.completed(stop_reason:)
        { kind: 'completed', stop_reason: stop_reason }
      end

      # 方法功能：创建错误数据块
      # 参数：message - 错误消息，code - 可选错误代码
      # 返回值：包含错误信息的哈希
      # 使用方法：传入错误消息和可选错误代码
      # @param message [String]
      # @param code [String, nil]
      # @return [Hash]
      def self.error(message:, code: nil)
        result = { kind: 'error', message: message }
        result[:code] = code if code
        result
      end
    end

    # 结构体功能：模型单轮请求数据结构
    # 使用方法：包含不可变前缀项、对话历史和当前工具列表
    ModelRequest = Struct.new(
      :thread_id,
      :turn_id,
      :model,
      :system_prompt,
      :mode_instruction,
      :context_instructions,
      :prefix,
      :history,
      :attachments,
      :attachment_text_fallbacks,
      :tools,
      :required_tool_name,
      :stream,
      :max_tokens,
      :temperature,
      :top_p,
      :response_format,
      :reasoning_effort,
      :abort_signal,
      keyword_init: true
    )

    # 结构体功能：模型输入附件数据结构
    # 使用方法：包含附件ID、名称、MIME类型、Base64数据、宽高等信息
    ModelInputAttachment = Struct.new(
      :id,
      :name,
      :mime_type,
      :data_base64,
      :width,
      :height,
      keyword_init: true
    )

    # 结构体功能：模型文本附件回退数据结构
    # 使用方法：包含附件元数据和压缩状态信息
    ModelTextAttachmentFallback = Struct.new(
      :id,
      :name,
      :mime_type,
      :data_base64,
      :byte_size,
      :width,
      :height,
      :was_compressed,
      keyword_init: true
    )

    # 结构体功能：模型工具规格数据结构
    # 使用方法：包含工具名称、描述、输入模式和工具类型
    ModelToolSpec = Struct.new(
      :name,
      :description,
      :input_schema,
      :tool_kind,
      keyword_init: true
    )

    # @abstract Subclass and implement {#stream}
    # Port for talking to a model provider. Adapters implement this with
    # a DeepSeek-compatible HTTP client, with `pi-ai`, or with a test
    # double. The loop never depends on a concrete implementation.

    # 类功能：模型客户端基类，定义与AI模型提供者通信的接口
    class ModelClient
      # 属性功能：获取提供者名称
      # @return [String]
      attr_reader :provider

      # 属性功能：获取模型名称
      # @return [String]
      attr_reader :model

      # 方法功能：初始化模型客户端
      # 参数：provider - 提供者名称，model - 模型名称
      # 使用方法：传入提供者和模型名称创建客户端实例
      # @param provider [String]
      # @param model [String]
      def initialize(provider:, model:)
        @provider = provider
        @model = model
      end

      # 方法功能：发起模型请求并返回流式响应
      # 参数：request - 模型请求对象
      # 返回值：流式数据块枚举器
      # 使用方法：传入模型请求，返回流式响应迭代器
      # @param request [ModelRequest]
      # @return [Enumerator<ModelStreamChunk>]
      def stream(request)
        raise NotImplementedError
      end
    end
  end
end
