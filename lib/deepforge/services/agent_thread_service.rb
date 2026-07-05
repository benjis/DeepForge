# frozen_string_literal: true

# 文件用途：线程服务
# 使用方法：管理线程的完整生命周期，包括创建、读取、更新、删除、分叉、会话恢复、
#           目标管理和待办事项管理。每个线程代表一个对话会话。

require_relative '../domain/model_history_repair'

module DeepForge
  module Services
    # 线程服务：拥有线程的增删改查、分叉、会话恢复、目标和待办事项管理。
    class AgentThreadService
      # 初始化线程服务
      # 参数：thread_store - 线程存储实例，session_store - 会话存储实例，
      #        events - 事件记录器，ids - ID 生成器，now_iso - 时间戳生成器（Proc）
      def initialize(thread_store:, session_store:, events:, ids:, now_iso:)
        @thread_store = thread_store
        @session_store = session_store
        @events = events
        @ids = ids
        @now_iso = now_iso
      end

      # 列出线程，支持搜索和过滤
      # 参数：options - 可选选项（含 search, archived_only, include_archived, include_side, limit）
      # 返回值：Array<Hash>，线程摘要列表
      def list(options = {})
        query = options[:search]&.strip&.downcase
        threads = @thread_store.list(options)

        if options[:archived_only]
          threads = threads.select { |t| t[:status] == 'archived' }
        elsif !options[:include_archived]
          threads = threads.reject { |t| %w[archived deleted].include?(t[:status]) }
        end

        threads = threads.reject { |t| (t[:relation] || 'primary') == 'side' } unless options[:include_side]

        threads = threads.select { |t| matches_thread_search?(t, query) } if query

        options[:limit] ? threads.first(options[:limit]) : threads
      end

      # 获取线程详情
      # 参数：thread_id - 线程 ID
      # 返回值：Hash 或 nil，线程记录
      def get(thread_id)
        @thread_store.get(thread_id)
      end

      # 创建新线程
      # 参数：request - 创建请求（含 workspace, model, mode 等），options - 可选选项（含 id, title, status）
      # 返回值：Hash，创建的线程记录
      def create(request, options = {})
        generated = @ids.next('thr')
        id = options[:id] || generated

        thread = create_thread_record(
          id: id,
          title: options[:title] || (request[:title]&.strip || 'New chat'),
          workspace: request[:workspace],
          model: request[:model],
          mode: request[:mode],
          approval_policy: request[:approval_policy],
          sandbox_mode: request[:sandbox_mode],
          cost_budget_usd: request[:cost_budget_usd],
          status: options[:status]
        )

        @thread_store.upsert(thread)
        @events.record(
          kind: 'thread_created',
          thread_id: thread[:id],
          title: thread[:title]
        )

        thread
      end

      # 更新线程属性
      # 参数：thread_id - 线程 ID，patch - 要更新的字段哈希
      # 返回值：Hash，更新后的线程记录
      def update(thread_id, patch)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current

        merged = current.merge(patch.except(:cost_budget_usd, :cost_budget_warning_sent))

        if patch[:cost_budget_usd].nil?
          merged.delete(:cost_budget_usd)
          merged.delete(:cost_budget_warning_sent)
        elsif patch.key?(:cost_budget_usd)
          merged[:cost_budget_usd] = patch[:cost_budget_usd]
          merged[:cost_budget_warning_sent] = false
        elsif patch.key?(:cost_budget_warning_sent)
          merged[:cost_budget_warning_sent] = patch[:cost_budget_warning_sent]
        end

        merged.delete(:parent_thread_id) if patch[:relation] && patch[:relation] != 'side'

        updated = touch_thread(merged, @now_iso.call)
        @thread_store.upsert(updated)
        @events.record(
          kind: 'thread_updated',
          thread_id: thread_id,
          title: updated[:title],
          status: updated[:status]
        )

        updated
      end

      # 获取线程的目标（goal）
      # 参数：thread_id - 线程 ID
      # 返回值：Hash 或 nil，目标记录（camelCase 格式）
      def get_goal(thread_id)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current

        goal_to_camel(current[:goal])
      end

      # 设置或更新线程的目标
      # 参数：thread_id - 线程 ID，request - 目标请求（含 objective, status, token_budget）
      # 返回值：Hash，目标记录（camelCase 格式）
      def set_goal(thread_id, request)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current

        # Accept both snake_case and camelCase keys
        obj = request[:objective] || request['objective']
        st = request[:status] || request['status']
        tb = request[:token_budget] || request['tokenBudget']
        raise "cannot update goal for thread #{thread_id}: no goal exists" if current[:goal].nil? && obj.nil?

        now = @now_iso.call
        existing = current[:goal]
        objective = obj&.strip

        goal = {
          thread_id: thread_id,
          objective: objective || existing&.dig(:objective) || '',
          status: st || (objective ? 'active' : existing&.dig(:status) || 'active'),
          token_budget: tb || existing&.dig(:token_budget),
          tokens_used: existing&.dig(:tokens_used) || 0,
          time_used_seconds: existing&.dig(:time_used_seconds) || 0,
          created_at: existing&.dig(:created_at) || now,
          updated_at: now
        }

        goal.delete(:token_budget) if goal[:token_budget].nil?

        updated = touch_thread(current.merge(goal: goal), now)
        @thread_store.upsert(updated)
        @events.record(
          kind: 'goal_updated',
          thread_id: thread_id,
          goal: goal
        )

        goal_to_camel(goal)
      end

      # 清除线程的目标
      # 参数：thread_id - 线程 ID
      # 返回值：Boolean，是否成功清除
      def clear_goal(thread_id)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current
        return false unless current[:goal]

        updated = touch_thread(current.dup, @now_iso.call)
        updated.delete(:goal)
        @thread_store.upsert(updated)
        @events.record(
          kind: 'goal_cleared',
          thread_id: thread_id,
          cleared: true
        )

        true
      end

      # 获取线程的待办事项列表
      # 参数：thread_id - 线程 ID
      # 返回值：Hash 或 nil，待办事项记录
      def get_todos(thread_id)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current

        current[:todos]
      end

      # 设置或更新线程的待办事项列表
      # 参数：thread_id - 线程 ID，request - 待办事项请求（含 todos 数组）
      # 返回值：Hash，更新后的待办事项记录
      def set_todos(thread_id, request)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current

        now = @now_iso.call
        items = normalize_todo_items(
          raw_items: request[:todos],
          existing_items: current.dig(:todos, :items) || [],
          now: now,
          ids: @ids
        )

        in_progress_count = items.count { |i| i[:status] == 'in_progress' }
        raise ArgumentError, 'at most one todo can be in_progress' if in_progress_count > 1

        patch_plan_markdown_for_todo_status_changes(current, items)

        todos = {
          thread_id: thread_id,
          items: items,
          updated_at: now
        }

        updated = touch_thread(current.merge(todos: todos), now)
        @thread_store.upsert(updated)
        @events.record(
          kind: 'todos_updated',
          thread_id: thread_id,
          todos: todos
        )

        todos
      end

      # 清除线程的待办事项列表
      # 参数：thread_id - 线程 ID
      # 返回值：Boolean，是否成功清除
      def clear_todos(thread_id)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current
        return false unless current[:todos]

        updated = touch_thread(current.dup, @now_iso.call)
        updated.delete(:todos)
        @thread_store.upsert(updated)
        @events.record(
          kind: 'todos_cleared',
          thread_id: thread_id,
          cleared: true
        )

        true
      end

      # 从计划文件同步待办事项
      # 参数：thread_id - 线程 ID，options - 同步选项（含 relative_path, markdown, plan_id 等）
      # 返回值：Hash，更新后的待办事项记录
      def sync_todos_from_plan(thread_id, options)
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current

        relative_path = Shared.normalize_plan_relative_path(options[:relative_path])
        unless Shared.gui_plan_relative_path?(relative_path)
          raise "invalid GUI plan relative path: #{options[:relative_path]}"
        end

        now = @now_iso.call
        plan_items = Shared.extract_plan_todos(
          markdown: options[:markdown],
          plan_id: options[:plan_id],
          relative_path: relative_path,
          thread_id: thread_id,
          now: now
        )

        todos = Shared.merge_plan_todos(Shared::MergePlanTodosOptions.new(
                                          thread_id: thread_id,
                                          existing: current[:todos],
                                          plan_items: plan_items,
                                          now: now,
                                          preserve_completed: options.fetch(:preserve_completed, true)
                                        ))

        updated = touch_thread(current.merge(todos: todos), now)
        @thread_store.upsert(updated)
        @events.record(
          kind: 'todos_updated',
          thread_id: thread_id,
          todos: todos
        )

        todos
      end

      # 删除指定线程
      # 参数：thread_id - 线程 ID
      # 返回值：Boolean，是否成功删除
      def delete(thread_id)
        @thread_store.delete(thread_id)
      end

      # 分叉线程，创建一个新的线程并复制原线程的历史
      # 参数：thread_id - 源线程 ID，options - 分叉选项（含 relation, title 等）
      # 返回值：Hash，分叉后的线程记录
      def fork(thread_id, options = {})
        current = @thread_store.get(thread_id)
        raise "thread not found: #{thread_id}" unless current

        now = @now_iso.call
        fork_id = @ids.next('thr')
        relation = options[:relation] || 'fork'

        cloned_turns = current[:turns]&.map do |turn|
          clone_turn_for_fork(turn, fork_id, now, relation: relation)
        end || []

        cloned_items = cloned_turns.flat_map { |t| t[:items] }
        default_title = relation == 'side' ? "#{current[:title]} · side" : "#{current[:title]} fork"

        fork = create_thread_record(
          id: fork_id,
          title: options[:title]&.strip || default_title,
          workspace: current[:workspace],
          model: current[:model],
          mode: current[:mode],
          status: 'idle',
          approval_policy: current[:approval_policy],
          sandbox_mode: current[:sandbox_mode],
          relation: relation,
          parent_thread_id: current[:id],
          forked_from_thread_id: current[:id],
          forked_from_title: current[:title],
          forked_at: now,
          forked_from_message_count: cloned_items.count { |i| i[:kind] == 'user_message' },
          forked_from_turn_count: cloned_turns.length,
          todos: current[:todos] ? clone_todo_list_for_thread(current[:todos], fork_id, now) : nil,
          created_at: now
        )

        record = fork.merge(updated_at: now, turns: cloned_turns)

        cloned_items.each do |item|
          @session_store.append_item(record[:id], item)
        end

        @thread_store.upsert(record)
        @events.record(
          kind: 'thread_created',
          thread_id: record[:id],
          title: record[:title]
        )

        record
      end

      # 从已有会话恢复，创建新线程并复制源会话的历史
      # 参数：session_id - 源会话 ID，options - 恢复选项（含 workspace, model, mode）
      # 返回值：Hash（含 thread, session_id, message_count）
      def resume_session(session_id, options = {})
        source_thread = @thread_store.get(session_id)
        source_session = @session_store.load_session(session_id)
        source_items = if source_thread
                         source_thread[:turns]&.flat_map { |t| t[:items] } || []
                       elsif source_session&.dig(:items)&.any?
                         source_session[:items]
                       else
                         @session_store.load_items(session_id)
                       end

        raise "session not found: #{session_id}" unless source_thread || source_session || source_items.any?

        now = @now_iso.call
        thread_id = @ids.next('thr')

        source_turns = if source_thread
                         source_thread[:turns] || []
                       else
                         rebuild_turns_from_items(
                           items: source_items,
                           thread_id: thread_id,
                           fallback_turn_id: source_session&.dig(:turn_id) || @ids.next('turn'),
                           fallback_prompt: "Resumed session #{session_id[0...8]}",
                           now: now
                         )
                       end

        cloned_turns = source_turns.map { |turn| clone_turn_for_thread(turn, thread_id, now) }
        cloned_items = cloned_turns.flat_map { |t| t[:items] }
        source_title = source_thread&.dig(:title) || "Session #{session_id[0...8]}"

        record = create_thread_record(
          id: thread_id,
          title: "#{source_title} resumed",
          workspace: options[:workspace] || source_thread&.dig(:workspace) || '~',
          model: options[:model] || source_thread&.dig(:model) || DeepForge::Config::DEFAULT_DEEPFORGE_MODEL,
          mode: options[:mode] || source_thread&.dig(:mode) || 'agent',
          status: 'idle',
          approval_policy: source_thread&.dig(:approval_policy),
          sandbox_mode: source_thread&.dig(:sandbox_mode),
          forked_from_thread_id: source_thread&.dig(:id),
          forked_from_title: source_thread&.dig(:title),
          forked_at: now,
          forked_from_message_count: cloned_items.count { |i| i[:kind] == 'user_message' },
          forked_from_turn_count: cloned_turns.length,
          todos: source_thread&.dig(:todos) ? clone_todo_list_for_thread(source_thread[:todos], thread_id, now) : nil,
          created_at: now
        )

        resumed = record.merge(updated_at: now, turns: cloned_turns)

        cloned_items.each do |item|
          @session_store.append_item(resumed[:id], item)
        end

        @thread_store.upsert(resumed)
        @session_store.upsert_session(to_session_snapshot(resumed, now))
        @events.record(
          kind: 'thread_created',
          thread_id: resumed[:id],
          title: resumed[:title]
        )

        { thread: resumed, session_id: session_id, message_count: cloned_items.length }
      end

      # 将线程转换为摘要格式
      # 参数：thread - 完整线程记录
      # 返回值：Hash，线程摘要
      def to_summary(thread)
        to_thread_summary(thread)
      end

      private

      # 内部方法：将线程转换为摘要格式
      def to_thread_summary(thread)
        {
          id: thread[:id],
          title: thread[:title],
          workspace: thread[:workspace],
          model: thread[:model],
          mode: thread[:mode],
          status: thread[:status],
          cost_budget_usd: thread[:cost_budget_usd],
          cost_budget_warning_sent: thread[:cost_budget_warning_sent],
          relation: thread[:relation],
          parent_thread_id: thread[:parent_thread_id],
          forked_from_thread_id: thread[:forked_from_thread_id],
          forked_from_title: thread[:forked_from_title],
          forked_at: thread[:forked_at],
          forked_from_message_count: thread[:forked_from_message_count],
          forked_from_turn_count: thread[:forked_from_turn_count],
          goal: thread[:goal],
          todos: thread[:todos],
          created_at: thread[:created_at],
          updated_at: thread[:updated_at]
        }
      end

      # 创建线程记录（内部方法）
      def create_thread_record(attrs)
        now = @now_iso.call
        # Helper to get value with snake_case or camelCase key
        get = ->(snake, camel = nil) { attrs[snake] || (camel && attrs[camel]) }
        {
          id: attrs[:id],
          title: attrs[:title] || 'New chat',
          workspace: attrs[:workspace],
          model: attrs[:model],
          mode: attrs[:mode],
          status: attrs[:status] || 'idle',
          approval_policy: get.call(:approval_policy, :approvalPolicy),
          sandbox_mode: get.call(:sandbox_mode, :sandboxMode),
          cost_budget_usd: get.call(:cost_budget_usd, :costBudgetUsd),
          relation: attrs[:relation],
          parent_thread_id: get.call(:parent_thread_id, :parentThreadId),
          forked_from_thread_id: get.call(:forked_from_thread_id, :forkedFromThreadId),
          forked_from_title: get.call(:forked_from_title, :forkedFromTitle),
          forked_at: get.call(:forked_at, :forkedAt),
          forked_from_message_count: get.call(:forked_from_message_count, :forkedFromMessageCount),
          forked_from_turn_count: get.call(:forked_from_turn_count, :forkedFromTurnCount),
          todos: attrs[:todos],
          goal: attrs[:goal],
          turns: attrs[:turns] || [],
          created_at: attrs[:created_at] || now,
          updated_at: now
        }
      end

      # 更新线程的最后修改时间（内部方法）
      def touch_thread(thread, now)
        thread.merge(updated_at: now)
      end

      # 将目标从 snake_case 转换为 camelCase（用于 API 响应）
      def goal_to_camel(goal)
        return nil unless goal

        {
          threadId: goal[:thread_id] || goal['thread_id'],
          objective: goal[:objective] || goal['objective'],
          status: goal[:status] || goal['status'],
          tokenBudget: goal[:token_budget] || goal['tokenBudget'],
          tokensUsed: goal[:tokens_used] || goal['tokensUsed'] || 0,
          timeUsedSeconds: goal[:time_used_seconds] || goal['timeUsedSeconds'] || 0,
          createdAt: goal[:created_at] || goal['createdAt'],
          updatedAt: goal[:updated_at] || goal['updatedAt']
        }.compact
      end

      # 当待办事项状态变化时，更新对应的计划文件中的 Markdown 状态（内部方法）
      def patch_plan_markdown_for_todo_status_changes(current, next_items)
        previous_by_id = (current.dig(:todos, :items) || []).to_h { |item| [item[:id], item] }
        changed_plan_items = next_items.select do |item|
          next false unless item[:source]&.dig(:kind) == 'plan'

          previous = previous_by_id[item[:id]]
          previous.nil? || previous[:status] != item[:status]
        end
        return if changed_plan_items.empty?

        by_relative_path = {}
        changed_plan_items.each do |item|
          source = item[:source]
          next unless source&.dig(:kind) == 'plan'

          relative_path = Shared.normalize_plan_relative_path(source[:relative_path])
          unless Shared.gui_plan_relative_path?(relative_path)
            raise "invalid GUI plan relative path: #{source[:relative_path]}"
          end

          by_relative_path[relative_path] ||= []
          by_relative_path[relative_path] << item
        end

        by_relative_path.each do |relative_path, items|
          absolute_path = resolve_workspace_relative_path(current[:workspace], relative_path)
          markdown = File.read(absolute_path)
          changed = false

          items.each do |item|
            patched = Shared.patch_plan_todo_status(markdown, Contracts::ThreadTodoItem.new(
                                                                content: item[:content],
                                                                status: item[:status],
                                                                source: normalize_todo_source(item[:source])
                                                              ))
            markdown = patched[:markdown]
            changed = true if patched[:changed]
          end

          File.write(absolute_path, markdown) if changed
        end
      end

      # 将相对路径解析为工作区内的绝对路径（内部方法，含路径逃逸检查）
      def resolve_workspace_relative_path(workspace, relative_path)
        root = File.expand_path(workspace)
        target = File.expand_path(relative_path, root)
        from_root = begin
          Pathname.new(target).relative_path_from(Pathname.new(root)).to_s
        rescue ArgumentError
          nil
        end

        if from_root.nil? || from_root.start_with?('..') || (from_root.start_with?('/') && !from_root.start_with?(root))
          raise "plan path escapes workspace: #{relative_path}"
        end

        target
      end

      # 判断线程是否匹配搜索关键词（内部方法）
      def matches_thread_search?(thread, query)
        [
          thread[:id],
          thread[:title],
          thread[:workspace],
          thread[:model],
          thread[:mode],
          thread[:forked_from_title],
          thread[:forked_from_thread_id]
        ].any? { |v| v&.downcase&.include?(query) }
      end

      # 克隆轮次用于线程复制（内部方法）
      def clone_turn_for_thread(turn, thread_id, now)
        items = turn[:items]&.map { |i| clone_item_for_thread(i, thread_id, now) } || []
        items = DeepForge::Domain.repair_model_history_items(items)
        attachment_ids = turn[:attachment_ids]&.any? ? turn[:attachment_ids] : attachment_ids_from_items(items)

        turn.merge(
          thread_id: thread_id,
          status: %w[queued running].include?(turn[:status]) ? 'completed' : turn[:status],
          finished_at: turn[:finished_at] || now,
          attachment_ids: attachment_ids,
          items: items
        )
      end

      # 克隆轮次用于分叉操作（内部方法）
      def clone_turn_for_fork(turn, thread_id, now, relation:)
        in_flight = %w[queued running].include?(turn[:status])

        if relation == 'side' && in_flight
          user_prompt_item = turn[:items]&.find { |i| i[:kind] == 'user_message' }
          user_prompt_item_cloned = user_prompt_item ? clone_item_for_thread(user_prompt_item, thread_id, now) : nil

          return turn.merge(
            thread_id: thread_id,
            status: 'aborted',
            finished_at: turn[:finished_at] || now,
            attachment_ids: if turn[:attachment_ids]&.any?
                              turn[:attachment_ids]
                            else
                              attachment_ids_from_items(user_prompt_item_cloned ? [user_prompt_item_cloned] : [])
                            end,
            items: user_prompt_item_cloned ? [user_prompt_item_cloned] : []
          )
        end

        clone_turn_for_thread(turn, thread_id, now)
      end

      # 克隆消息项用于线程复制（内部方法）
      def clone_item_for_thread(item, thread_id, now)
        cloned = item.merge(thread_id: thread_id)

        if %w[pending running].include?(cloned[:status])
          case cloned[:kind]
          when 'approval'
            return cloned.merge(status: 'expired', finished_at: cloned[:finished_at] || now)
          when 'user_input'
            return cloned.merge(status: 'cancelled', finished_at: cloned[:finished_at] || now)
          else
            return cloned.merge(status: 'completed', finished_at: cloned[:finished_at] || now)
          end
        end

        cloned
      end

      # 从消息项中提取附件 ID 列表（内部方法）
      def attachment_ids_from_items(items)
        ids = Set.new
        items.each do |item|
          next unless item[:kind] == 'user_message'

          (item[:attachment_ids] || []).each do |id|
            trimmed = id.strip
            ids.add(trimmed) if trimmed.any?
          end
        end
        ids.to_a
      end

      # 将线程转换为会话快照格式（内部方法）
      def to_session_snapshot(thread, now)
        first_turn = thread[:turns]&.first
        {
          thread_id: thread[:id],
          turn_id: first_turn&.dig(:id) || '',
          started_at: first_turn&.dig(:created_at) || thread[:created_at],
          updated_at: now,
          items: thread[:turns]&.flat_map { |t| t[:items] } || [],
          events: [],
          closed: true
        }
      end

      # 从消息项列表重建轮次结构（内部方法，用于会话恢复）
      def rebuild_turns_from_items(items:, thread_id:, fallback_turn_id:, fallback_prompt:, now:)
        by_turn = {}
        items.each do |item|
          turn_id = item[:turn_id] || fallback_turn_id
          by_turn[turn_id] ||= []
          by_turn[turn_id] << item.merge(thread_id: thread_id)
        end

        if by_turn.empty?
          return [{
            id: fallback_turn_id,
            thread_id: thread_id,
            status: 'completed',
            prompt: fallback_prompt,
            steering: [],
            attachment_ids: [],
            active_skill_ids: [],
            injected_memory_ids: [],
            created_at: now,
            finished_at: now,
            items: []
          }]
        end

        by_turn.map do |turn_id, turn_items|
          prompt = turn_items.find { |i| i[:kind] == 'user_message' }&.dig(:text) || fallback_prompt
          {
            id: turn_id,
            thread_id: thread_id,
            status: 'completed',
            prompt: prompt,
            steering: [],
            attachment_ids: attachment_ids_from_items(turn_items),
            active_skill_ids: [],
            injected_memory_ids: [],
            created_at: turn_items.first&.dig(:created_at) || now,
            finished_at: now,
            items: turn_items
          }
        end
      end

      # 克隆待办事项列表用于线程复制（内部方法）
      def clone_todo_list_for_thread(todos, thread_id, now)
        {
          thread_id: thread_id,
          items: todos[:items]&.map(&:dup) || [],
          updated_at: now
        }
      end

      # 标准化待办事项列表，合并已有项和新项（内部方法）
      def normalize_todo_items(raw_items:, existing_items:, now:, ids:)
        existing_by_id = existing_items.to_h { |item| [item[:id], item] }
        used_ids = Set.new
        in_progress_seen = false

        raw_items.map do |raw|
          content = raw[:content]&.strip
          raise 'todo content is required' if content.nil? || content.empty?

          status = normalize_todo_status(raw[:status])
          if status == 'in_progress'
            raise 'at most one todo can be in_progress' if in_progress_seen

            in_progress_seen = true
          end

          source = raw[:source] ? normalize_todo_source(raw[:source]) : nil
          requested_id = raw[:id]&.strip
          existing = (requested_id ? existing_by_id[requested_id] : nil) ||
                     find_existing_todo_for_raw(existing_items, used_ids, content: content, source: source)

          id = unique_todo_id(requested_id || existing&.dig(:id) || ids.next('todo'), used_ids, ids)
          changed = !existing || existing[:content] != content || existing[:status] != status || !same_todo_source?(
            existing[:source], source
          )
          used_ids.add(id)

          {
            id: id,
            content: content,
            status: status,
            source: source,
            created_at: existing&.dig(:created_at) || now,
            updated_at: changed ? now : existing&.dig(:updated_at)
          }.compact
        end
      end

      # 标准化待办事项状态值（内部方法）
      def normalize_todo_status(status)
        return status if %w[pending in_progress completed].include?(status)

        raise "unsupported todo status: #{status}"
      end

      # 标准化待办事项来源信息（内部方法）
      def normalize_todo_source(source)
        raise "unsupported todo source: #{source[:kind]}" unless source[:kind] == 'plan'

        relative_path = normalize_plan_relative_path(source[:relative_path])
        {
          kind: 'plan',
          plan_id: source[:plan_id],
          relative_path: relative_path,
          ordinal: source[:ordinal],
          content_hash: source[:content_hash]
        }
      end

      # 标准化计划文件的相对路径（内部方法）
      def normalize_plan_relative_path(path)
        path.strip
      end

      # 根据内容和来源查找已存在的待办事项（内部方法）
      def find_existing_todo_for_raw(existing_items, used_ids, content:, source: nil)
        candidates = existing_items.reject { |item| used_ids.include?(item[:id]) }

        if source
          return candidates.find { |item| item[:source] && same_todo_source?(item[:source], source) } ||
                 candidates.find do |item|
                   item[:source]&.dig(:kind) == 'plan' &&
                   item[:source][:plan_id] == source[:plan_id] &&
                   item[:source][:relative_path] == source[:relative_path] &&
                   item[:source][:content_hash] == source[:content_hash]
                 end ||
                 candidates.find do |item|
                   item[:source]&.dig(:kind) == 'plan' &&
                   item[:source][:plan_id] == source[:plan_id] &&
                   item[:source][:relative_path] == source[:relative_path] &&
                   item[:source][:ordinal] == source[:ordinal]
                 end
        end

        hash = todo_content_hash(content)
        candidates.find { |item| item[:source].nil? && todo_content_hash(item[:content]) == hash }
      end

      # 比较两个待办事项来源是否相同（内部方法）
      def same_todo_source?(first, second)
        return true if first.nil? && second.nil?
        return false if first.nil? || second.nil?

        first[:kind] == second[:kind] &&
          first[:plan_id] == second[:plan_id] &&
          first[:relative_path] == second[:relative_path] &&
          first[:ordinal] == second[:ordinal] &&
          first[:content_hash] == second[:content_hash]
      end

      # 计算待办事项内容的哈希值（用于匹配）（内部方法）
      def todo_content_hash(content)
        Digest::SHA256.hexdigest(content.strip.downcase)
      end

      # 生成唯一的待办事项 ID（内部方法）
      def unique_todo_id(requested, used_ids, ids)
        candidate = requested.strip
        candidate = ids.next('todo') while candidate.empty? || used_ids.include?(candidate)
        candidate
      end
    end
  end
end
