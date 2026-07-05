# frozen_string_literal: true

# 文件用途：运行中任务追踪器，管理模型和工具工作的生命周期
# 使用方法：通过 InflightTracker.new 创建实例
# 追踪器是 SSE 事件流的权威来源：每次 begin 对应一对 tool_call_started/tool_call_finished

# 类功能：运行中任务追踪器
# 使用稳定 ID 追踪运行中的模型和工具工作，保证成功、错误和取消时的清理
module DeepForge
  module Loop
    class InflightTracker
      # 运行中记录的数据结构
      InflightRecord = Struct.new(
        :id,
        :kind,
        :thread_id,
        :turn_id,
        :call_id,
        :started_at,
        keyword_init: true
      )

      # 初始化追踪器
      def initialize
        @entries = {}
      end

      # 注册新的运行中记录
      # @param record [Hash] 记录属性（不含 started_at）
      # @return [InflightRecord] 完整记录
      def begin(record)
        full = InflightRecord.new(
          id: record[:id],
          kind: record[:kind],
          thread_id: record[:thread_id],
          turn_id: record[:turn_id],
          call_id: record[:call_id],
          started_at: record[:started_at] || (Time.now.to_f * 1000).to_i
        )
        @entries[full.id] = full
        full
      end

      # 结束运行中记录的追踪
      # @param id [String] 记录 ID
      # @return [InflightRecord, nil] 已结束的记录或 nil
      def end(id)
        @entries.delete(id)
      end

      # 使用运行中追踪执行代码块
      # @param record [Hash] 记录属性
      # @yield 要执行的工作
      # @return [Object] 代码块的返回值
      def run(record)
        self.begin(record)
        yield
      ensure
        self.end(record[:id])
      end

      # 获取运行中记录
      # @param id [String] 记录 ID
      # @return [InflightRecord, nil] 记录或 nil
      def get(id)
        @entries[id]
      end

      # 检查记录是否存在
      # @param id [String] 记录 ID
      # @return [Boolean] 记录是否存在
      def has?(id)
        @entries.key?(id)
      end

      # 获取所有运行中记录
      # @return [Array<InflightRecord] 所有运行中记录
      def list
        @entries.values
      end

      # 取消所有运行中记录
      # @param reason [String] 取消原因
      # @return [Array<String>] 已取消的记录 ID 和原因列表
      def abort_all(reason = 'aborted')
        ids = @entries.keys.dup
        @entries.clear
        ids.map { |id| "#{id}:#{reason}" }
      end

      # 获取运行中记录数量
      # @return [Integer] 运行中记录数量
      def size
        @entries.size
      end
    end
  end
end
