# frozen_string_literal: true

# 文件用途：目标自动恢复协调器，管理目标模式下的跨轮次恢复策略
# 使用方法：通过 GoalResumeCoordinator.new(deps) 创建实例
# 当目标轮次异常结束时自动安排恢复，支持指数退避和进度追踪

module DeepForge
  module Loop
    # 类功能：目标自动恢复协调器
    # 管理目标模式下的跨轮次恢复策略，包括：
    # - 失败目标轮次后的恢复启动
    # - 运行时重启后中断目标的恢复
    # - 连续无进展失败的指数退避限制
    class GoalResumeCoordinator
      # 阻止目标前的最大连续无进展失败次数
      DEFAULT_MAX_GOAL_RESUME_NO_PROGRESS_ATTEMPTS = 5

      # 指数退避的基础延迟（毫秒）
      DEFAULT_GOAL_RESUME_BASE_DELAY_MS = 2_000

      # 指数退避的最大延迟（毫秒）
      DEFAULT_GOAL_RESUME_MAX_DELAY_MS = 60_000

      # 可取消的定时回调
      # @!method cancel
      #   取消待执行的定时器
      GoalResumeTimer = Struct.new(:cancel)

      # 注入到协调器的依赖项
      #
      # @!attribute launch
      #   @return [Proc] 启动线程活跃目标的新延续轮次
      # @!attribute get_active_goal_key
      #   @return [Proc] 重新读取线程目标并在活跃时返回稳定键
      # @!attribute is_thread_busy
      #   @return [Proc] 线程当前是否有轮次在运行
      # @!attribute set_timer
      #   @return [Proc, nil] 调度延迟回调（可被测试覆盖）
      # @!attribute log
      #   @return [Proc, nil] 诊断输出（默认使用 warn）
      # @!attribute max_no_progress_attempts
      #   @return [Integer, nil] 允许的连续无进展失败次数
      # @!attribute base_delay_ms
      #   @return [Integer, nil] 退避基础延迟
      # @!attribute max_delay_ms
      #   @return [Integer, nil] 退避最大延迟
      GoalResumeCoordinatorDeps = Struct.new(
        :launch, :get_active_goal_key, :is_thread_busy,
        :set_timer, :log, :max_no_progress_attempts,
        :base_delay_ms, :max_delay_ms,
        keyword_init: true
      )

      # 线程级别的恢复状态，用于追踪尝试次数
      #
      # @!attribute goal_key
      #   @return [String] 正在追踪的目标键
      # @!attribute attempts
      #   @return [Integer] 连续无进展恢复尝试次数
      # @!attribute timer
      #   @return [GoalResumeTimer, nil] 待执行的退避定时器
      ThreadResumeState = Struct.new(:goal_key, :attempts, :timer, keyword_init: true)

      # 初始化协调器
      # @param deps [GoalResumeCoordinatorDeps] 注入的依赖项
      def initialize(deps)
        @deps = deps
        @set_timer = deps.set_timer || method(:default_set_timer)
        @max_no_progress_attempts = deps.max_no_progress_attempts || DEFAULT_MAX_GOAL_RESUME_NO_PROGRESS_ATTEMPTS
        @base_delay_ms = deps.base_delay_ms || DEFAULT_GOAL_RESUME_BASE_DELAY_MS
        @max_delay_ms = deps.max_delay_ms || DEFAULT_GOAL_RESUME_MAX_DELAY_MS
        @state = {}
        @shutting_down = false
      end

      # 记录目标轮次失败并安排退避恢复
      #
      # 当连续无进展预算用尽时返回 'exhausted'——调用者应将目标移出 `active` 状态
      #
      # @param thread_id [String] 线程标识符
      # @param goal_key [String] 失败轮次的目标键
      # @param made_progress [Boolean] 轮次是否取得了有意义的进展
      # @return ['scheduled', 'exhausted', 'skipped'] 恢复结果
      def note_goal_turn_failed(thread_id:, goal_key:, made_progress:)
        return 'skipped' if @shutting_down

        entry = @state[thread_id]
        if entry.nil? || entry.goal_key != goal_key
          entry&.timer&.cancel
          entry = ThreadResumeState.new(goal_key: goal_key, attempts: 0)
          @state[thread_id] = entry
        end

        entry.timer&.cancel
        entry.timer = nil

        # A failure that still made progress resets the streak, so a long goal
        # that keeps advancing always reschedules and is never blocked; only a
        # run of *consecutive* no-progress failures burns the budget.
        if made_progress
          entry.attempts = 0
        else
          entry.attempts += 1
        end

        if entry.attempts > @max_no_progress_attempts
          @state.delete(thread_id)
          return 'exhausted'
        end

        delay_ms = [
          @max_delay_ms,
          @base_delay_ms * (2**[0, entry.attempts - 1].max)
        ].min

        entry.timer = @set_timer.call(-> { fire(thread_id, goal_key) }, delay_ms)
        'scheduled'
      end

      # 恢复因运行时重启而中断的目标（路径 A）
      #
      # 立即启动（需重新验证）并初始化无进展计数器，
      # 使后续恢复轮次的失败从零开始计数
      #
      # @param thread_id [String] 线程标识符
      # @return [Boolean] 恢复是否已启动
      def resume_interrupted(thread_id)
        return false if @shutting_down

        begin
          goal_key = @deps.get_active_goal_key.call(thread_id)
          return false if goal_key.nil?
          return false if @deps.is_thread_busy.call(thread_id)

          @state[thread_id]&.timer&.cancel
          @state[thread_id] = ThreadResumeState.new(goal_key: goal_key, attempts: 0)

          @deps.launch.call(thread_id)
          true
        rescue StandardError => e
          log_message("goal resume on startup failed for #{thread_id}: #{e}")
          false
        end
      end

      # 清除线程的所有待恢复状态
      #
      # 在目标完成、清除或轮次成功时调用
      #
      # @param thread_id [String] 线程标识符
      # @return [void]
      def clear(thread_id)
        entry = @state[thread_id]
        return if entry.nil?

        entry.timer&.cancel
        @state.delete(thread_id)
      end

      # 取消所有待恢复状态，在运行时关闭时调用
      #
      # @return [void]
      def shutdown
        @shutting_down = true
        @state.each_value { |entry| entry.timer&.cancel }
        @state.clear
      end

      private

      # 在退避延迟后触发恢复回调
      #
      # @param thread_id [String] 线程标识符
      # @param goal_key [String] 要验证的目标键
      # @return [void]
      # @api private
      def fire(thread_id, goal_key)
        return if @shutting_down

        entry = @state[thread_id]
        return if entry.nil? || entry.goal_key != goal_key

        entry.timer = nil

        begin
          current_key = @deps.get_active_goal_key.call(thread_id)

          if current_key != goal_key
            # Goal completed, blocked, paused, cleared, or replaced while we waited.
            @state.delete(thread_id)
            return
          end

          return if @deps.is_thread_busy.call(thread_id)

          @deps.launch.call(thread_id)
        rescue StandardError => e
          log_message("goal resume launch failed for #{thread_id}: #{e}")
        end
      end

      # 记录诊断消息
      #
      # @param message [String] 要记录的消息
      # @return [void]
      # @api private
      def log_message(message)
        if @deps.log
          @deps.log.call(message)
        else
          warn "[deepforge] #{message}"
        end
      end

      # 使用 Thread 的默认定时器实现
      #
      # @param fn [Proc] 要执行的回调
      # @param delay_ms [Integer] 延迟毫秒数
      # @return [GoalResumeTimer] 可取消的定时器句柄
      # @api private
      def default_set_timer(fn, delay_ms)
        thread = Thread.new do
          sleep(delay_ms / 1000.0)
          fn.call
        end

        GoalResumeTimer.new(-> { thread.kill if thread.alive? })
      end
    end
  end
end
