# frozen_string_literal: true

# 文件用途：仅追加的会话日志，支持有界内存窗口和完整磁盘回放
# 使用方法：通过 AppendOnlySessionLog.new(window_size) 创建日志实例
# 内存窗口是快速访问路径；旧事件从内存中淘汰并存储在文件后端

# 类功能：仅追加的会话日志管理器
# 维护一个有界内存窗口，支持追加条目和事件，超出窗口大小的旧数据自动淘汰
module DeepForge
  module Loop
    class AppendOnlySessionLog
      # 初始化会话日志
      # @param window_size [Integer] 内存中保留的最大条目/事件数量
      def initialize(window_size = 1_000)
        @window_size = [1, window_size].max
        @session = nil
      end

      # 加载已有会话
      # @param session [Hash] 要加载的会话对象
      def load(session)
        @session = session
      end

      # 确保会话存在，若不存在则创建
      # @param input [Hash] 会话输入参数
      # @return [Hash] 会话对象
      def ensure_session(input)
        @session ||= create_session(input)
        @session
      end

      # 向会话追加一个条目
      # @param item [Hash] 要追加的条目
      # @return [Hash] 更新后的会话
      def append_item(item)
        @session = if @session
                     append_session_item(@session, item)
                   else
                     append_session_item(
                       create_session(thread_id: item[:thread_id], turn_id: item[:turn_id]),
                       item
                     )
                   end
        evict
        @session
      end

      # 向会话追加一个事件
      # @param event [Hash] 要追加的事件
      # @return [Hash] 更新后的会话
      def append_event(event)
        @session = if @session
                     append_session_event(@session, event)
                   else
                     append_session_event(
                       create_session(thread_id: event[:thread_id], turn_id: event[:turn_id] || ''),
                       event
                     )
                   end
        evict
        @session
      end

      # 获取当前会话
      # @return [Hash, nil] 当前会话对象
      def current
        @session
      end

      # 获取所有条目
      # @return [Array<Hash>] 条目列表
      def items
        @session&.dig(:items) || []
      end

      # 获取所有事件
      # @return [Array<Hash>] 事件列表
      def events
        @session&.dig(:events) || []
      end

      private

      # 创建新会话
      # @param input [Hash] 会话输入参数
      # @return [Hash] 新会话对象
      def create_session(input)
        {
          thread_id: input[:thread_id],
          turn_id: input[:turn_id],
          items: [],
          events: []
        }
      end

      # 向会话追加条目（内部方法）
      # @param session [Hash] 会话对象
      # @param item [Hash] 条目
      # @return [Hash] 更新后的会话
      def append_session_item(session, item)
        session.merge(items: session[:items] + [item])
      end

      # 向会话追加事件（内部方法）
      # @param session [Hash] 会话对象
      # @param event [Hash] 事件
      # @return [Hash] 更新后的会话
      def append_session_event(session, event)
        session.merge(events: session[:events] + [event])
      end

      # 从内存中淘汰超出窗口大小的旧条目和事件
      def evict
        return unless @session

        @session = @session.merge(items: @session[:items].last(@window_size)) if @session[:items].length > @window_size
        return unless @session[:events].length > @window_size

        @session = @session.merge(events: @session[:events].last(@window_size))
      end
    end
  end
end
