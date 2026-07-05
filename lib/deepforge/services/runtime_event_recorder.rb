# frozen_string_literal: true

# 文件用途：运行时事件记录器
# 使用方法：作为应用层的事件边界，接收服务和循环产生的语义事件草稿，
#           添加排序序号和时间戳，验证公共契约，分发给实时订阅者，并持久化用于 SSE 重放。

require_relative '../contracts/events'

module DeepForge
  module Services
    # 应用级事件边界。
    #
    # 服务和循环产生语义事件草稿；此记录器为事件添加排序序号/时间戳，
    # 验证公共契约，分发给实时订阅者，并持久化事件用于 SSE 重放。
    class RuntimeEventRecorder
      # 初始化事件记录器
      # 参数：event_bus - 事件总线实例，session_store - 会话存储实例，
      #        allocate_seq - 序列号分配器（Proc），now_iso - 时间戳生成器（Proc）
      def initialize(event_bus:, session_store:, allocate_seq:, now_iso:)
        @event_bus = event_bus
        @session_store = session_store
        @allocate_seq = allocate_seq
        @now_iso = now_iso
      end

      # 记录一个事件草稿，添加序列号和时间戳，发布到事件总线并持久化到会话存储
      # 参数：draft - 事件草稿哈希，必须包含 :thread_id 和 :kind 键
      # 返回值：Hash，完整事件（含 seq 和 timestamp）
      def record(draft)
        validate_event_draft!(draft)

        allocated_seq = @allocate_seq.call(draft[:thread_id])
        persisted_seq = @session_store.highest_seq(draft[:thread_id])

        event = draft.merge(
          seq: draft[:seq] || [allocated_seq, persisted_seq + 1].max,
          timestamp: draft[:timestamp] || @now_iso.call
        )

        @event_bus.publish(event[:thread_id], event)
        @session_store.append_event(event[:thread_id], event)

        event
      end

      private

      # 需要 turn_id 的事件类型常量列表
      TURN_REQUIRING_KINDS = %w[
        turn_started
        turn_completed
        turn_failed
        turn_aborted
        turn_steered
      ].freeze

      # 验证事件草稿的有效性（内部方法）
      # 参数：draft - 事件草稿哈希
      # 异常：ArgumentError，当缺少必要字段或事件类型无效时
      def validate_event_draft!(draft)
        thread_id = draft[:thread_id]
        raise ArgumentError, 'Event draft must have a non-empty thread_id' if thread_id.nil? || thread_id.to_s.empty?

        kind = draft[:kind]
        raise ArgumentError, 'Event draft must have a non-empty kind' if kind.nil? || kind.to_s.empty?

        valid_kinds = Contracts::RuntimeEventKind.constants(false).map { |c| c.to_s.downcase }
        raise ArgumentError, "Unknown event kind: #{kind.inspect}" unless valid_kinds.include?(kind.to_s)

        return unless TURN_REQUIRING_KINDS.include?(kind.to_s)

        turn_id = draft[:turn_id]
        return unless turn_id.nil? || turn_id.to_s.empty?

        raise ArgumentError,
              "Event kind #{kind.inspect} requires a non-empty turn_id"
      end
    end
  end
end
