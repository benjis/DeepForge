# frozen_string_literal: true

# 文件用途：压缩历史管理工具，提供会话历史中压缩标记的管理功能
# 使用方法：通过 DeepForge::Loop::CompactionHistory 模块的类方法调用

require_relative '../contracts/items'

module DeepForge
  module Loop
    # 模块功能：压缩历史管理工具
    # 提供查找有效历史、插入压缩摘要、重新排序条目等功能
    module CompactionHistory
      # 查找最近一次压缩标记后的有效历史
      # 从条目数组末尾向前扫描，找到最近一个 replaced_tokens > 0 的压缩标记，返回该点之后的所有条目
      #
      # @param items [Array<TurnItem>] 会话条目列表
      # @return [Array<TurnItem] 从最近压缩点开始的条目
      def self.effective_history_after_latest_compaction(items)
        items.each_with_index.reverse_each do |item, index|
          return items[index..] if item[:kind] == 'compaction' && item[:replaced_tokens]&.positive?
        end
        items.dup
      end

      # 将压缩摘要插入到可见历史中的正确位置
      #
      # @param visible_items [Array<TurnItem>] 用户可见的条目
      # @param compacted_items [Array<TurnItem>] 压缩后的条目
      # @param summary_item [TurnItem] 要插入的压缩摘要
      # @return [Array<TurnItem] 正确定位摘要后的历史
      def self.insert_compaction_into_visible_history(visible_items:, compacted_items:, summary_item:)
        summary_index = compacted_items.index { |item| item[:id] == summary_item[:id] }
        return replace_or_append_item(visible_items, summary_item) if summary_index.nil? || summary_index.negative?

        tail_ids = compacted_items[(summary_index + 1)..].to_set { |item| item[:id] }
        without_summary = visible_items.reject { |item| item[:id] == summary_item[:id] }

        return [*without_summary, summary_item] if tail_ids.empty?

        insert_index = without_summary.index { |item| tail_ids.include?(item[:id]) }
        return [*without_summary, summary_item] if insert_index.nil?

        [
          *without_summary[0...insert_index],
          summary_item,
          *without_summary[insert_index..]
        ]
      end

      # 重新排列轮次条目，使压缩摘要位于末尾
      #
      # 会话存储布局保持 [头部, 摘要, 尾部]，使 effective_history_after_latest_compaction
      # 为模型返回 [摘要, 尾部]。但线程存储布局驱动渲染器的 groupTurns，
      # 它在每个用户消息处分割块——将摘要留在扁平位置会将其推入前一轮次的时间线。
      # 将摘要移到其所属轮次桶的末尾可确保渲染器在实际发生压缩的轮次内显示它。
      #
      # @param items [Array<TurnItem>] 待重新排列的条目
      # @return [Array<TurnItem>] 压缩标记位于末尾的条目
      def self.place_compactions_at_turn_end(items)
        has_trailing = items.any? do |item|
          item[:kind] == 'compaction' && item[:replaced_tokens]&.positive?
        end
        return items.dup unless has_trailing

        rest = []
        trailing = []

        items.each do |item|
          if item[:kind] == 'compaction' && item[:replaced_tokens]&.positive?
            trailing << item
          else
            rest << item
          end
        end

        [*rest, *trailing]
      end

      # 替换或追加列表中的条目（内部方法）
      #
      # @param items [Array<TurnItem>] 已有条目
      # @param item [TurnItem] 要替换或追加的条目
      # @return [Array<TurnItem] 更新后的条目
      # @api private
      def self.replace_or_append_item(items, item)
        index = items.index { |existing| existing[:id] == item[:id] }
        return items + [item] if index.nil?

        items.map { |existing| existing[:id] == item[:id] ? item : existing }
      end
      private_class_method :replace_or_append_item
    end
  end
end
