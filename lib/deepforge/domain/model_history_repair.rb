# frozen_string_literal: true

# 文件用途：修复持久化的轮次项目，使其符合模型发送的历史格式
# 使用方法：用于清理项目列表，确保每个工具调用都有对应的工具结果

module DeepForge
  module Domain
    # 修复模型历史项目：将 GUI 专用项目与模型绑定的工具调用分离
    # DeepForge 存储了 GUI 专用项目（如审批、用户输入提示、推理块）与模型绑定的工具调用
    # Provider API 要求每个助手工具调用块必须紧跟一个匹配的结果
    def self.repair_model_history_items(items)
      kept_call_indexes = Set.new
      kept_result_indexes = Set.new

      index = 0
      while index < items.length
        item = items[index]
        if item.kind != 'tool_call'
          index += 1
          next
        end

        calls = []
        seen_call_ids = Set.new
        cursor = index
        while cursor < items.length && items[cursor].kind == 'tool_call'
          call = items[cursor]
          unless seen_call_ids.include?(call.call_id)
            seen_call_ids.add(call.call_id)
            calls << { item: call, index: cursor }
          end
          cursor += 1
        end

        result = find_result_block(items, cursor, { turn_id: item.turn_id, expected_call_ids: seen_call_ids })
        if calls.any? && result[:result_call_ids].any?
          calls.each do |call|
            kept_call_indexes.add(call[:index]) if result[:result_call_ids].include?(call[:item].call_id)
          end
          result[:result_indexes].each { |i| kept_result_indexes.add(i) }
        end

        index = cursor
      end

      changed = false
      repaired = items.each_with_index.select do |item, item_index|
        keep = if item.kind == 'tool_call'
                 kept_call_indexes.include?(item_index)
               elsif item.kind == 'tool_result'
                 kept_result_indexes.include?(item_index)
               else
                 true
               end
        changed = true unless keep
        keep
      end.map(&:first)

      changed ? repaired : items
    end

    # 判断项目是否为工具结果桥接项：可以出现在工具调用和结果之间的项目类型
    def self.tool_result_bridge_item?(item, options)
      case item.kind
      when 'assistant_reasoning', 'approval', 'user_input', 'error'
        true
      when 'assistant_text'
        !options[:saw_result] && item.turn_id == options[:turn_id]
      else
        false
      end
    end

    # 查找结果块：从指定位置开始查找与工具调用匹配的结果项目
    def self.find_result_block(items, start_index, options)
      seen_result_ids = Set.new
      result_indexes = []
      saw_result = false
      index = start_index

      while index < items.length
        item = items[index]
        break unless item

        if item.kind == 'tool_result'
          saw_result = true
          if options[:expected_call_ids].include?(item.call_id) && !seen_result_ids.include?(item.call_id)
            seen_result_ids.add(item.call_id)
            result_indexes << index
          end
          index += 1
          next
        end

        if tool_result_bridge_item?(item, { turn_id: options[:turn_id], saw_result: saw_result })
          index += 1
          next
        end

        break
      end

      { result_call_ids: seen_result_ids, result_indexes: result_indexes }
    end
  end
end
