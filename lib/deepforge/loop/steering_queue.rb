# frozen_string_literal: true

# 文件用途：轮次中转向队列，收集渲染器在轮次运行时发布的转向文本
# 使用方法：通过 SteeringQueue.new 创建实例
# 队列在轮次完成或中断时清空

# 类功能：轮次中转向队列
# 收集渲染器发布的转向消息，在下一个安全循环边界注入为用户输入
module DeepForge
  module Loop
    class SteeringQueue
      # 初始化转向队列
      def initialize
        @buffer = []
        @turn_id = nil
      end

      # 设置活跃轮次 ID，变更时清空缓冲区
      # @param turn_id [String, nil] 轮次 ID
      def set_turn(turn_id)
        @buffer.clear unless @turn_id == turn_id
        @turn_id = turn_id
      end

      # 入队转向消息
      # @param turn_id [String] 轮次 ID
      # @param text [String] 转向文本
      def enqueue(turn_id, text)
        unless @turn_id == turn_id
          @buffer.clear
          @turn_id = turn_id
        end
        trimmed = text.strip
        return if trimmed.empty?

        @buffer.push(trimmed)
      end

      # 排空队列中的转向消息并返回
      # @return [Array<String>] 队列中的消息
      def drain
        return [] if @buffer.empty?

        out = @buffer.dup
        @buffer.clear
        out
      end

      # 查看队列中的文本但不移除
      # @return [Array<String>] 队列中的消息
      def peek
        @buffer.dup
      end

      # 清空队列并重置轮次 ID
      def clear
        @buffer.clear
        @turn_id = nil
      end
    end
  end
end
