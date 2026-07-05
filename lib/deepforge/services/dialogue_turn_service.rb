# frozen_string_literal: true

# 文件用途：轮次服务
# 使用方法：管理对话轮次的完整生命周期，包括开始、结束、中断、引导和压缩。
#           每个轮次对应用户的一次请求和模型的一次响应。

module DeepForge
  module Services
    # 轮次服务：拥有轮次的完整生命周期（开始、结束、中断、引导、压缩）。
    class DialogueTurnService
      # 轮次中断信号结构体，用于判断轮次是否被中断
      # 替代了 Concurrent::Promises.resolvable_future 的用法
      AbortSignal = Struct.new(:rejected_reason, keyword_init: true) do
        # 判断轮次是否已被中断
        def rejected?
          !rejected_reason.nil?
        end

        # 中断轮次，设置中断原因
        def reject(reason)
          self.rejected_reason = reason
        end
      end

      # 初始化轮次服务
      # 参数：deps - 依赖注入哈希（含 thread_store, session_store, events, inflight,
      #        steering, compactor, ids, now_iso 等）
      def initialize(deps)
        @deps = deps
        @inflight_turns = {}
        @thread_mutation_queues = {}
      end

      # 开始一个新的对话轮次
      # 参数：thread_id - 线程 ID，request - 请求哈希（含 prompt, model, reasoning_effort 等）
      # 返回值：Hash（含 thread_id, turn_id, user_message_item_id）
      def start_turn(thread_id:, request:)
        thread = @deps[:thread_store].get(thread_id)
        raise "thread not found: #{thread_id}" unless thread

        turn_id = @deps[:ids].next('turn')
        turn = create_turn_record(
          id: turn_id,
          thread_id: thread_id,
          prompt: request[:prompt],
          model: request[:model],
          reasoning_effort: request[:reasoning_effort],
          attachment_ids: request[:attachment_ids] || [],
          gui_plan: request[:gui_plan],
          mode: request[:mode]
        )

        user_item = make_user_item(
          id: "item_#{turn_id}_user",
          turn_id: turn_id,
          thread_id: thread_id,
          text: request[:prompt],
          display_text: request[:display_text],
          attachment_ids: request[:attachment_ids] || []
        )

        upsert_thread(thread_id) do |current|
          touch_thread(current, @deps[:now_iso].call).merge(
            status: 'running',
            turns: (current[:turns] || []) + [start_turn_record(append_turn_item(turn, user_item))]
          )
        end

        @deps[:session_store].append_item(thread_id, user_item)

        @deps[:events].record(
          kind: 'turn_started',
          thread_id: thread_id,
          turn_id: turn_id
        )

        @deps[:events].record(
          kind: 'item_created',
          thread_id: thread_id,
          turn_id: turn_id,
          item_id: user_item[:id],
          item: user_item
        )

        @inflight_turns[turn_id] = AbortSignal.new
        @deps[:inflight].begin(id: turn_id, kind: 'model', thread_id: thread_id, turn_id: turn_id)
        @deps[:steering].set_turn(turn_id)

        { thread_id: thread_id, turn_id: turn_id, user_message_item_id: user_item[:id] }
      end

      # 向正在运行的轮次发送引导指令
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID，text - 引导文本
      # 返回值：void
      def steer_turn(thread_id:, turn_id:, text:)
        @deps[:steering].enqueue(turn_id, text)
        @deps[:events].record(
          kind: 'turn_steered',
          thread_id: thread_id,
          turn_id: turn_id,
          text: text
        )
      end

      # 中断一个正在运行的轮次
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID，discard - 是否丢弃轮次消息（默认 false）
      # 返回值：Hash（含 :status 键，值为 'aborted'）
      def interrupt_turn(thread_id:, turn_id:, discard: false)
        controller = @inflight_turns.delete(turn_id)
        controller&.reject('interrupted')

        @deps[:steering].clear
        @deps[:inflight].end(turn_id)

        @deps[:events].record(
          kind: 'turn_aborted',
          thread_id: thread_id,
          turn_id: turn_id
        )

        discard_turn_items(thread_id, turn_id) if discard

        upsert_thread(thread_id) do |current|
          turn = current[:turns]&.find { |t| t[:id] == turn_id }
          return current unless turn

          next_turns = (current[:turns] || []).map do |t|
            if t[:id] == turn_id
              finalized = finalize_open_items(
                finish_turn_record(discard ? t.merge(items: keep_user_items(t[:items])) : t, 'aborted'),
                'aborted'
              )
              finalized
            else
              t
            end
          end

          touch_thread(current, @deps[:now_iso].call).merge(turns: next_turns, status: 'idle')
        end

        { status: 'aborted' }
      end

      # 压缩线程的对话历史，减少 token 使用量
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID（可选），request - 压缩请求（含 budget_tokens, reason）
      # 返回值：Hash（含 replaced_tokens, summary 等压缩结果信息）
      def compact(thread_id:, request:, turn_id: nil)
        thread = @deps[:thread_store].get(thread_id)
        raise "thread not found: #{thread_id}" unless thread

        resolved_turn_id = turn_id || thread[:turns]&.last&.dig(:id) || @deps[:ids].next('turn')
        items = @deps[:session_store].load_items(thread_id)
        history = items.reject { |i| system_only_item?(i) }

        prefix = {
          system_prompt: '',
          tools: [],
          pinned_constraints: ['user: preserve recent turns'],
          few_shots: [],
          fingerprint: 'compact',
          revision: 0
        }

        result = @deps[:compactor].compact(
          thread_id: thread_id,
          turn_id: resolved_turn_id,
          history: history,
          prefix: prefix,
          budget_tokens: request[:budget_tokens],
          reason: request[:reason]
        )

        append_item(thread_id, result[:summary_item]) if result[:replaced_tokens]&.positive?

        @deps[:events].record(
          kind: 'compaction_completed',
          thread_id: thread_id,
          turn_id: resolved_turn_id,
          item_id: result[:summary_item][:id],
          summary: result[:summary_item][:kind] == 'compaction' ? result[:summary_item][:summary] : '',
          replaced_tokens: result[:replaced_tokens],
          pinned_constraints: prefix[:pinned_constraints],
          source_digest: result[:summary_item][:source_digest],
          digest_marker: result[:summary_item][:digest_marker],
          source_item_ids: result[:summary_item][:source_item_ids]
        ).compact

        {
          thread_id: thread_id,
          replaced_tokens: result[:replaced_tokens],
          summary: result[:summary_item][:kind] == 'compaction' ? result[:summary_item][:summary] : '',
          pinned_constraints: prefix[:pinned_constraints],
          source_digest: result[:summary_item][:source_digest],
          digest_marker: result[:summary_item][:digest_marker],
          source_item_ids: result[:summary_item][:source_item_ids]
        }.compact
      end

      # 完成一个轮次，更新状态和发布事件
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID，status - 完成状态，error - 错误信息（可选）
      # 返回值：void
      def finish_turn(thread_id:, turn_id:, status:, error: nil)
        @inflight_turns.delete(turn_id)
        @deps[:inflight].end(turn_id)
        @deps[:steering].clear

        upsert_thread(thread_id) do |current|
          next_turns = (current[:turns] || []).map do |t|
            if t[:id] == turn_id
              finished = finalize_open_items(finish_turn_record(t, status), status)
              error ? finished.merge(error: error) : finished
            else
              t
            end
          end

          touch_thread(current, @deps[:now_iso].call).merge(turns: next_turns, status: 'idle')
        end

        event_kind = case status
                     when 'completed' then 'turn_completed'
                     when 'aborted' then 'turn_aborted'
                     else 'turn_failed'
                     end

        event = {
          kind: event_kind,
          thread_id: thread_id,
          turn_id: turn_id
        }
        event[:message] = error if error
        @deps[:events].record(event)

        return unless error

        append_item(thread_id, make_error_item(
                                 id: "item_#{turn_id}_error",
                                 turn_id: turn_id,
                                 thread_id: thread_id,
                                 message: error
                               ))
      end

      # 获取指定轮次的中断控制器
      # 参数：turn_id - 轮次 ID
      # 返回值：AbortSignal 或 nil
      def get_abort_controller(turn_id)
        @inflight_turns[turn_id]
      end

      # 获取指定轮次的详情
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID
      # 返回值：Hash 或 nil，轮次记录
      def get_turn(thread_id, turn_id)
        thread = @deps[:thread_store].get(thread_id)
        thread[:turns]&.find { |t| t[:id] == turn_id }
      end

      # 更新轮次的元数据（如技能 ID、注入记忆 ID 等）
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID，patch - 要更新的字段哈希
      # 返回值：void
      def update_turn_metadata(thread_id, turn_id, patch)
        upsert_thread(thread_id) do |current|
          current.merge(
            turns: (current[:turns] || []).map do |turn|
              if turn[:id] == turn_id
                turn.merge(
                  **(patch[:active_skill_ids] ? { active_skill_ids: patch[:active_skill_ids].dup } : {}),
                  **(patch[:injected_memory_ids] ? { injected_memory_ids: patch[:injected_memory_ids].dup } : {}),
                  **(patch.key?(:skill_injection_bytes) ? { skill_injection_bytes: patch[:skill_injection_bytes] } : {}),
                  **(patch[:tool_catalog_fingerprint] ? { tool_catalog_fingerprint: patch[:tool_catalog_fingerprint] } : {}),
                  **(patch.key?(:tool_catalog_tool_count) ? { tool_catalog_tool_count: patch[:tool_catalog_tool_count] } : {}),
                  **(patch.key?(:tool_catalog_drift) ? { tool_catalog_drift: patch[:tool_catalog_drift] } : {})
                )
              else
                turn
              end
            end
          )
        end
      end

      # 向轮次应用一个消息项并发布创建事件
      # 参数：thread_id - 线程 ID，item - 消息项哈希
      # 返回值：void
      def apply_item(thread_id, item)
        append_item(thread_id, item)
        @deps[:events].record(
          kind: 'item_created',
          thread_id: thread_id,
          turn_id: item[:turn_id],
          item_id: item[:id],
          item: item
        )
      end

      # 更新指定消息项的部分字段
      # 参数：thread_id - 线程 ID，item_id - 消息项 ID，patch - 要更新的字段哈希
      # 返回值：Hash 或 nil，更新后的消息项
      def update_item(thread_id, item_id, patch)
        updated_in_session = @deps[:session_store].update_item(thread_id, item_id, patch)
        updated_items = []

        upsert_thread(thread_id) do |current|
          turns = (current[:turns] || []).map do |turn|
            existing = turn[:items]&.find { |i| i[:id] == item_id }
            next turn unless existing

            updated_items[0] = existing.merge(patch)
            replace_turn_item(turn, item_id, patch)
          end

          current.merge(turns: turns)
        end

        updated = updated_items[0] || updated_in_session
        return nil unless updated

        @deps[:events].record(
          kind: 'item_updated',
          thread_id: thread_id,
          turn_id: updated[:turn_id],
          item_id: updated[:id],
          item: updated
        )

        updated
      end

      private

      # 创建新的轮次记录（内部方法）
      # 参数：attrs - 轮次属性哈希
      # 返回值：Hash，轮次记录
      def create_turn_record(attrs)
        now = @deps[:now_iso].call
        {
          id: attrs[:id],
          thread_id: attrs[:thread_id],
          status: 'running',
          prompt: attrs[:prompt],
          model: attrs[:model],
          reasoning_effort: attrs[:reasoning_effort],
          attachment_ids: attrs[:attachment_ids] || [],
          gui_plan: attrs[:gui_plan],
          mode: attrs[:mode],
          steering: [],
          active_skill_ids: [],
          injected_memory_ids: [],
          created_at: now,
          finished_at: nil,
          items: []
        }
      end

      # 将轮次标记为已开始状态（内部方法）
      # 参数：turn - 轮次记录
      # 返回值：Hash，更新后的轮次记录
      def start_turn_record(turn)
        turn.merge(status: 'running', started_at: @deps[:now_iso].call)
      end

      # 将轮次标记为已完成状态（内部方法）
      # 参数：turn - 轮次记录，status - 完成状态
      # 返回值：Hash，更新后的轮次记录
      def finish_turn_record(turn, status)
        turn.merge(
          status: status,
          finished_at: @deps[:now_iso].call
        )
      end

      # 向轮次追加一个消息项（内部方法）
      # 参数：turn - 轮次记录，item - 消息项
      # 返回值：Hash，更新后的轮次记录
      def append_turn_item(turn, item)
        turn.merge(items: (turn[:items] || []) + [item])
      end

      # 替换轮次中指定消息项的内容（内部方法）
      # 参数：turn - 轮次记录，item_id - 消息项 ID，patch - 更新内容
      # 返回值：Hash，更新后的轮次记录
      def replace_turn_item(turn, item_id, patch)
        turn.merge(
          items: (turn[:items] || []).map do |item|
            item[:id] == item_id ? item.merge(patch) : item
          end
        )
      end

      # 创建用户消息项（内部方法）
      # 参数：attrs - 消息项属性（含 id, turn_id, thread_id, text 等）
      # 返回值：Hash，用户消息项
      def make_user_item(attrs)
        {
          id: attrs[:id],
          turn_id: attrs[:turn_id],
          thread_id: attrs[:thread_id],
          kind: 'user_message',
          text: attrs[:text],
          display_text: attrs[:display_text],
          attachment_ids: attrs[:attachment_ids],
          status: 'completed',
          created_at: @deps[:now_iso].call,
          finished_at: @deps[:now_iso].call
        }
      end

      # 创建错误消息项（内部方法）
      # 参数：attrs - 消息项属性（含 id, turn_id, thread_id, message 等）
      # 返回值：Hash，错误消息项
      def make_error_item(attrs)
        {
          id: attrs[:id],
          turn_id: attrs[:turn_id],
          thread_id: attrs[:thread_id],
          kind: 'error',
          message: attrs[:message],
          status: 'completed',
          created_at: @deps[:now_iso].call,
          finished_at: @deps[:now_iso].call
        }
      end

      # 向会话存储追加消息项并更新线程记录（内部方法）
      # 参数：thread_id - 线程 ID，item - 消息项
      # 返回值：void
      def append_item(thread_id, item)
        @deps[:session_store].append_item(thread_id, item)
        upsert_thread(thread_id) do |current|
          turn = current[:turns]&.find { |t| t[:id] == item[:turn_id] }
          return current unless turn

          next_turn = append_turn_item(turn, item)
          turns = (current[:turns] || []).map { |t| t[:id] == item[:turn_id] ? next_turn : t }
          current.merge(turns: turns)
        end
      end

      # 线程安全地更新线程记录（内部方法，使用互斥锁）
      # 参数：thread_id - 线程 ID，mutator - 更新函数（Proc）
      # 返回值：void
      def upsert_thread(thread_id, &mutator)
        @thread_mutation_queues[thread_id] ||= Mutex.new
        @thread_mutation_queues[thread_id].synchronize do
          current = @deps[:thread_store].get(thread_id)
          return unless current

          next_val = mutator.call(current)
          @deps[:thread_store].upsert(next_val.merge(updated_at: @deps[:now_iso].call))
        end
      end

      # 终结轮次中所有未完成的消息项（内部方法）
      # 参数：turn - 轮次记录，status - 终结状态
      # 返回值：Hash，更新后的轮次记录
      def finalize_open_items(turn, status)
        finished_at = @deps[:now_iso].call
        changed = false

        items = (turn[:items] || []).map do |item|
          next_item = finalize_open_item(item, status, finished_at)
          changed = true if next_item != item
          next_item
        end

        changed ? turn.merge(items: items) : turn
      end

      # 终结单个未完成的消息项（内部方法）
      # 参数：item - 消息项，status - 终结状态，finished_at - 完成时间
      # 返回值：Hash，更新后的消息项
      def finalize_open_item(item, status, finished_at)
        return item unless %w[pending running].include?(item[:status])

        case item[:kind]
        when 'approval'
          item.merge(status: 'expired', finished_at: finished_at)
        when 'user_input'
          item.merge(status: 'cancelled', finished_at: finished_at)
        else
          item_status = status == 'completed' ? 'completed' : status
          item.merge(status: item_status, finished_at: finished_at)
        end
      end

      # 丢弃指定轮次的消息项（仅保留用户消息）（内部方法）
      # 参数：thread_id - 线程 ID，turn_id - 轮次 ID
      # 返回值：void
      def discard_turn_items(thread_id, turn_id)
        items = @deps[:session_store].load_items(thread_id)
        @deps[:session_store].rewrite_items(
          thread_id,
          items.select { |i| i[:turn_id] != turn_id || i[:kind] == 'user_message' }
        )
      end

      # 仅保留用户消息项（内部方法）
      # 参数：items - 消息项列表
      # 返回值：Array<Hash>，过滤后的用户消息项列表
      def keep_user_items(items)
        items.select { |i| i[:kind] == 'user_message' }
      end

      # 判断消息项是否仅包含系统内容（内部方法）
      # 参数：item - 消息项
      # 返回值：Boolean
      def system_only_item?(item)
        %w[compaction error].include?(item[:kind])
      end

      # 更新线程的最后修改时间（内部方法）
      # 参数：thread - 线程记录，now - 当前时间 ISO 字符串
      # 返回值：Hash，更新后的线程记录
      def touch_thread(thread, now)
        thread.merge(updated_at: now)
      end
    end
  end
end
