# frozen_string_literal: true

# 文件用途：事件流路由模块，构建 SSE（Server-Sent Events）响应用于实时事件推送
# 使用方法：通过 GET /v1/threads/:id/events 端点建立 SSE 连接

require 'json'
require_relative '../middleware/sse'

module DeepForge
  module Server
    module Routes
      # 心跳间隔（毫秒），用于保持 SSE 连接活跃
      HEARTBEAT_INTERVAL_MS = 15_000

      # 构建 SSE 事件流响应
      # @param input [Hash] 输入参数，包含请求、线程 ID、事件总线等
      # @return [Hash] SSE 响应，包含流式响应体
      def self.build_event_stream_response(input)
        url = URI(input[:request][:url])
        query_params = URI.decode_www_form(url.query || '').to_h
        since_seq_from_query = (query_params['since_seq'] || '0').to_i
        since_seq_from_header = (input[:request][:headers]['last-event-id'] || '0').to_i
        since_seq = since_seq_from_query.positive? ? since_seq_from_query : since_seq_from_header

        # Return a response that will be streamed by the HTTP server
        {
          status: 200,
          headers: {
            'content-type' => 'text/event-stream; charset=utf-8',
            'cache-control' => 'no-cache, no-transform',
            'connection' => 'keep-alive'
          },
          body: proc do |yield_chunk|
            # Replay persisted events
            backlog = input[:session_store].load_events_since(input[:thread_id], since_seq)
            backlog.each do |event|
              yield_chunk.call(DeepForge::Server.encode_sse_event(event))
            end

            # Subscribe to live events
            unsubscribe = input[:event_bus].subscribe(input[:thread_id]) do |event|
              yield_chunk.call(DeepForge::Server.encode_sse_event(event))
            end

            # Heartbeat timer
            heartbeat_timer = Thread.new do
              loop do
                sleep(HEARTBEAT_INTERVAL_MS / 1000.0)
                heartbeat = {
                  kind: 'heartbeat',
                  seq: input[:allocate_seq].call(input[:thread_id]),
                  timestamp: Time.now.utc.strftime('%FT%TZ'),
                  thread_id: input[:thread_id]
                }
                yield_chunk.call(DeepForge::Server.encode_sse_event(heartbeat))
              end
            end

            # Wait for client disconnect
            input[:request][:wait]&.wait

            # Cleanup
            unsubscribe&.call
            heartbeat_timer&.kill
          rescue StandardError => e
            error_event = "event: error\ndata: #{JSON.generate({ message: e.message })}\n\n"
            yield_chunk.call(error_event)
          end
        }
      end
    end
  end
end
