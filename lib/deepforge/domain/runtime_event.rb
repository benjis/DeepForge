# frozen_string_literal: true

# 文件用途：定义事件的领域模型和工具方法
# 使用方法：用于事件比较、分组和排序

module DeepForge
  module Domain
    # 事件实体类型：引用运行时事件的联合类型
    RuntimeEventEntity = Contracts::RuntimeEvent

    # 比较两个事件的序号：用于 SSE 重放和事件追踪器确定事件顺序
    # 参数：a - 第一个事件；b - 第二个事件
    # 返回值：负数表示 a 在 b 之前，正数表示 a 在 b 之后，零表示相等
    def self.compare_event_seq(a, b)
      a.seq - b.seq
    end

    # 按类型分组事件：用于事件映射器计算聊天块转换和测试断言
    # 参数：events - 事件数组
    # 返回值：以事件类型为键、事件数组为值的哈希
    def self.group_events_by_kind(events)
      events.each_with_object({}) do |event, out|
        out[event.kind] ||= []
        out[event.kind] << event
      end
    end
  end
end
