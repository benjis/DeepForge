# frozen_string_literal: true

# 文件用途：计划待办事项（Todo）管理模块
# 使用方法：提供从 Markdown 中提取待办事项、合并待办列表、
#           更新待办状态等功能，用于计划文件的待办事项同步。

require_relative '../contracts/threads'

module DeepForge
  module Shared
    # 匹配 Markdown 待办事项行的正则表达式
    TASK_LINE_RE = /^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.+?)\s*$/

    # 提取的计划待办事项结构体
    ExtractedPlanTodo = Struct.new(:id, :content, :status, :source, :created_at, :updated_at, keyword_init: true)

    # 合并计划待办事项的选项结构体
    MergePlanTodosOptions = Struct.new(
      :thread_id,
      :existing,
      :plan_items,
      :now,
      :preserve_completed,
      keyword_init: true
    )
    TASK_LINE_RE = /^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.+?)\s*$/

    ExtractedPlanTodo = Struct.new(:id, :content, :status, :source, :created_at, :updated_at, keyword_init: true)

    MergePlanTodosOptions = Struct.new(
      :thread_id,
      :existing,
      :plan_items,
      :now,
      :preserve_completed,
      keyword_init: true
    )

    # 方法功能：标准化待办事项内容，合并空白字符
    # 参数：value - 原始待办事项文本
    # 返回值：String - 标准化后的文本（去除多余空白）
    def self.normalize_todo_content(value)
      value.gsub(/\s+/, ' ').strip
    end

    # 方法功能：计算待办事项内容的 FNV-1a 哈希值
    # 参数：value - 待办事项内容文本
    # 返回值：String - 36 进制的哈希值字符串
    def self.todo_content_hash(value)
      normalized = normalize_todo_content(value).downcase
      hash = 0x811c9dc5
      normalized.each_byte do |byte|
        hash ^= byte
        hash = (hash * 0x01000193) & 0xFFFFFFFF
      end
      hash.to_s(36)
    end

    # 方法功能：生成计划待办事项的唯一 ID
    # 参数：input - 包含 plan_id、relative_path、ordinal、content_hash 的哈希
    # 返回值：String - 格式为 "todo_plan_<hash>" 的唯一标识符
    def self.make_plan_todo_id(input)
      base = "#{input[:plan_id]}:#{input[:relative_path]}:#{input[:ordinal]}:#{input[:content_hash]}"
      "todo_plan_#{todo_content_hash(base)}"
    end

    # 方法功能：从 Markdown 文本中提取计划待办事项
    # 参数：input - 包含 markdown、plan_id、relative_path、now 的哈希
    # 返回值：Array<ExtractedPlanTodo> - 提取的待办事项列表
    def self.extract_plan_todos(input)
      items = []
      lines = input[:markdown].split(/\r?\n/)
      ordinal = 0

      lines.each do |line|
        match = TASK_LINE_RE.match(line)
        next unless match

        content = normalize_todo_content(match[4] || '')
        next if content.empty?

        content_hash = todo_content_hash(content)
        source = Contracts::ThreadTodoSource.new(
          kind: 'plan',
          plan_id: input[:plan_id],
          relative_path: normalize_plan_relative_path(input[:relative_path]),
          ordinal: ordinal,
          content_hash: content_hash
        )
        items << ExtractedPlanTodo.new(
          id: make_plan_todo_id(plan_id: source.plan_id, relative_path: source.relative_path, ordinal: ordinal,
                                content_hash: content_hash),
          content: content,
          status: task_marker_to_status(match[2]),
          source: source,
          created_at: input[:now],
          updated_at: input[:now]
        )
        ordinal += 1
      end

      items
    end

    # 方法功能：合并计划待办事项与现有待办列表
    # 参数：options - MergePlanTodosOptions 结构体，包含合并选项
    # 返回值：Contracts::ThreadTodoList - 合并后的待办列表
    def self.merge_plan_todos(options)
      existing_items = options.existing&.items || []
      used_existing_ids = Set.new
      next_items = []

      options.plan_items.each do |plan_item|
        existing = find_existing_plan_todo(existing_items, used_existing_ids, plan_item)
        used_existing_ids.add(existing.id) if existing

        status = if existing && options.preserve_completed && existing.status == Contracts::ThreadTodoStatus::COMPLETED
                   existing.status
                 else
                   existing&.status || plan_item.status
                 end

        content_matches = existing && existing.content == plan_item.content && existing.status == status
        next_items << Contracts::ThreadTodoItem.new(
          id: existing&.id || plan_item.id,
          content: plan_item.content,
          status: status,
          source: plan_item.source,
          created_at: existing&.created_at || plan_item.created_at,
          updated_at: content_matches ? existing.updated_at : options.now
        )
      end

      existing_items.each do |item|
        next if used_existing_ids.include?(item.id)

        next_items << if item.source&.kind == 'plan'
                        Contracts::ThreadTodoItem.new(
                          id: item.id,
                          content: item.content,
                          status: item.status,
                          source: nil,
                          created_at: item.created_at,
                          updated_at: options.now
                        )
                      else
                        item
                      end
      end

      Contracts::ThreadTodoList.new(
        thread_id: options.thread_id,
        items: next_items,
        updated_at: options.now
      )
    end

    # 方法功能：更新 Markdown 中指定待办事项的状态标记
    # 参数：markdown - 原始 Markdown 文本
    #       item - 待更新的待办事项对象
    # 返回值：Hash - 包含更新后的 markdown 和是否修改的标志
    def self.patch_plan_todo_status(markdown, item)
      source = item.source
      return { markdown: markdown, changed: false } unless source&.kind == 'plan'

      lines = markdown.split(/\r?\n/)
      line_ending = markdown.include?("\r\n") ? "\r\n" : "\n"

      tasks = lines.filter_map.with_index do |line, line_index|
        match = TASK_LINE_RE.match(line)
        next unless match

        content = normalize_todo_content(match[4] || '')
        {
          line: line,
          line_index: line_index,
          match: match,
          content: content,
          content_hash: todo_content_hash(match[4] || '')
        }
      end.each_with_index.map { |entry, ordinal| entry.merge(ordinal: ordinal) }

      target = tasks.find { |t| t[:ordinal] == source.ordinal && t[:content_hash] == source.content_hash } ||
               tasks.find { |t| t[:content_hash] == source.content_hash } ||
               tasks.find { |t| t[:ordinal] == source.ordinal }

      return { markdown: markdown, changed: false } unless target

      marker = item.status == Contracts::ThreadTodoStatus::COMPLETED ? 'x' : ' '
      current_marker = target[:match][2] || ' '
      return { markdown: markdown, changed: false } if current_marker.downcase == marker

      lines[target[:line_index]] = target[:line].sub(TASK_LINE_RE, "\\1#{marker}\\3\\4")
      { markdown: lines.join(line_ending), changed: true }
    end

    # 方法功能：生成待办事项来源的唯一键
    # 参数：source - 待办事项来源信息
    # 返回值：String - 格式为 "kind:plan_id:relative_path:ordinal:content_hash" 的键
    def self.source_key(source)
      "#{source.kind}:#{source.plan_id}:#{source.relative_path}:#{source.ordinal}:#{source.content_hash}"
    end

    # 方法功能：标准化计划文件的相对路径
    # 参数：relative_path - 原始相对路径
    # 返回值：String - 标准化后的路径（统一斜杠、去除前导 ./）
    def self.normalize_plan_relative_path(relative_path)
      relative_path.tr('\\', '/').gsub(%r{/+}, '/').sub(%r{^\./}, '')
    end

    class << self
      private

      # 方法功能：将 Markdown 任务标记转换为待办状态
      # 参数：marker - 任务标记字符（'x' 或 ' '）
      # 返回值：String - 对应的待办状态（COMPLETED 或 PENDING）
      def task_marker_to_status(marker)
        marker&.downcase == 'x' ? Contracts::ThreadTodoStatus::COMPLETED : Contracts::ThreadTodoStatus::PENDING
      end

      # 方法功能：在现有待办列表中查找匹配的计划待办事项
      # 参数：existing_items - 现有待办事项列表
      #       used_existing_ids - 已使用的待办事项 ID 集合
      #       plan_item - 待匹配的计划待办事项
      # 返回值：Contracts::ThreadTodoItem 或 nil - 匹配的待办事项
      def find_existing_plan_todo(existing_items, used_existing_ids, plan_item)
        candidates = existing_items.reject { |item| used_existing_ids.include?(item.id) }

        candidates.find do |item|
          item.source&.kind == 'plan' &&
            item.source.plan_id == plan_item.source.plan_id &&
            item.source.relative_path == plan_item.source.relative_path &&
            item.source.content_hash == plan_item.source.content_hash
        end ||
          candidates.find do |item|
            item.source&.kind == 'plan' &&
              item.source.relative_path == plan_item.source.relative_path &&
              item.source.content_hash == plan_item.source.content_hash
          end ||
          candidates.find { |item| todo_content_hash(item.content) == plan_item.source.content_hash } ||
          candidates.find do |item|
            item.source&.kind == 'plan' &&
              item.source.plan_id == plan_item.source.plan_id &&
              item.source.relative_path == plan_item.source.relative_path &&
              item.source.ordinal == plan_item.source.ordinal
          end
      end
    end
  end
end
