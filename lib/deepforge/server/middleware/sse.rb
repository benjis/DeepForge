# frozen_string_literal: true

# 文件用途：SSE 编码模块，将运行时事件编码为 Server-Sent Events 格式
# 使用方法：调用 encode_sse_event 方法将事件哈希转换为 SSE 格式字符串

module DeepForge
  module Server
    # 将运行时事件编码为 SSE（Server-Sent Events）格式字符串
    # @param event [Hash] 运行时事件，包含 :seq、:kind 和其他字段
    # @return [String] SSE 格式的事件字符串
    def self.encode_sse_event(event)
      "id: #{event[:seq]}\nevent: #{event[:kind]}\ndata: #{JSON.generate(event)}\n\n"
    end
  end
end
