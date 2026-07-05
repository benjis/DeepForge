# frozen_string_literal: true

# 文件用途：历史修复模块，用于修复加载的会话条目中的问题
# 使用方法：通过 HistoryHealing.heal(items) 调用

# 模块功能：历史修复
# 对加载的会话条目进行标准化和修复，确保历史数据的一致性
module DeepForge
  module Loop
    module HistoryHealing
      module_function

      # 修复加载的历史条目
      # @param items [Array<Hash>] 加载的历史条目
      # @return [Hash] { items: Array<Hash>, changed: Boolean } 修复后的条目和是否变更的标志
      def heal(items)
        normalized = items.each_with_index.map { |item, index| normalize_loaded_item(item, index) }
                                          .compact
        repaired = repair_model_history_items(normalized)
        changed = items.to_json != repaired.to_json
        { items: repaired, changed: changed }
      end

      # 标准化加载的条目，修复缺失的 ID 和无效的类型
      # @param item [Hash] 待标准化的条目
      # @param index [Integer] 条目索引
      # @return [Hash, nil] 标准化后的条目或 nil（无效条目）
      def normalize_loaded_item(item, index)
        return nil unless item.is_a?(Hash)

        kind = item[:kind] || item['kind'] || ''
        return nil if kind.empty?

        id = item[:id] || item['id']
        id = "item_healed_#{index}_#{kind}" if id.nil? || id.strip.empty?

        base = item.merge(id: id)

        case kind
        when 'tool_call', 'tool_result'
          return nil unless item[:call_id] || item[:callId] || item['call_id']
          return nil unless item[:tool_name] || item[:toolName] || item['tool_name']

          base
        when 'assistant_text', 'assistant_reasoning', 'user_message', 'approval',
             'user_input', 'compaction', 'review', 'error'
          base
        end
      end

      # 模型历史修复占位符（简化版本）
      # @param items [Array<Hash>] 待修复的条目
      # @return [Array<Hash>] 修复后的条目
      def repair_model_history_items(items)
        # Simplified repair - in production this would call the full repair logic
        items
      end
    end
  end
end
