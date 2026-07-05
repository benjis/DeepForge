# frozen_string_literal: true

require 'json'
require 'fileutils'

# 文件用途：内存存储接口和基于文件的实现
# 使用方法：使用MemoryStore模块创建记录，使用FileMemoryStore类进行持久化存储

# 模块功能：内存存储接口，定义内存记录操作
module MemoryStore
  # 结构体功能：内存记录数据结构
  # 使用方法：包含ID、内容、作用域、工作区、项目等元数据
  MemoryRecord = Struct.new(
    :id,
    :content,
    :scope,
    :workspace,
    :project,
    :source_thread_id,
    :source_turn_id,
    :tags,
    :confidence,
    :created_at,
    :updated_at,
    :deleted_at,
    :disabled_at,
    keyword_init: true
  )

  # 方法功能：创建内存记录
  # 参数：id - 记录ID，content - 内容，scope - 作用域，workspace - 工作区，project - 项目
  #       source_thread_id - 源线程ID，source_turn_id - 源轮次ID，tags - 标签，confidence - 置信度
  # 返回值：创建的内存记录对象
  # 使用方法：传入必要参数创建内存记录，自动设置创建和更新时间
  # @param id [String] the memory ID
  # @param content [String] the content
  # @param scope [String] the scope (user/workspace/project)
  # @param workspace [String, nil] the workspace
  # @param project [String, nil] the project
  # @param source_thread_id [String, nil] the source thread ID
  # @param source_turn_id [String, nil] the source turn ID
  # @param tags [Array<String>] the tags
  # @param confidence [Float] the confidence score
  # @return [MemoryRecord] the created record
  def self.create_record(
    id:,
    content:,
    scope: 'workspace',
    workspace: nil,
    project: nil,
    source_thread_id: nil,
    source_turn_id: nil,
    tags: [],
    confidence: 1.0
  )
    now = Time.now.utc.strftime('%FT%TZ')
    MemoryRecord.new(
      id: id,
      content: content,
      scope: scope,
      workspace: workspace,
      project: project,
      source_thread_id: source_thread_id,
      source_turn_id: source_turn_id,
      tags: tags,
      confidence: confidence,
      created_at: now,
      updated_at: now
    )
  end

  # 方法功能：将内存记录转换为哈希
  # 参数：record - 内存记录对象
  # 返回值：哈希表示的记录数据
  # 使用方法：传入内存记录对象，返回包含所有字段的哈希
  # @param record [MemoryRecord] the record to convert to hash
  # @return [Hash] the hash representation
  def self.to_hash(record)
    {
      id: record.id,
      content: record.content,
      scope: record.scope,
      workspace: record.workspace,
      project: record.project,
      source_thread_id: record.source_thread_id,
      source_turn_id: record.source_turn_id,
      tags: record.tags,
      confidence: record.confidence,
      created_at: record.created_at,
      updated_at: record.updated_at,
      deleted_at: record.deleted_at,
      disabled_at: record.disabled_at
    }
  end

  # 方法功能：将哈希转换为内存记录
  # 参数：hash - 哈希数据
  # 返回值：内存记录对象
  # 使用方法：传入哈希数据，返回内存记录对象
  # @param hash [Hash] the hash to convert to record
  # @return [MemoryRecord] the record
  def self.from_hash(hash)
    MemoryRecord.new(
      id: hash['id'] || hash[:id],
      content: hash['content'] || hash[:content],
      scope: hash['scope'] || hash[:scope],
      workspace: hash['workspace'] || hash[:workspace],
      project: hash['project'] || hash[:project],
      source_thread_id: hash['source_thread_id'] || hash[:source_thread_id],
      source_turn_id: hash['source_turn_id'] || hash[:source_turn_id],
      tags: hash['tags'] || hash[:tags] || [],
      confidence: hash['confidence'] || hash[:confidence] || 1.0,
      created_at: hash['created_at'] || hash[:created_at],
      updated_at: hash['updated_at'] || hash[:updated_at],
      deleted_at: hash['deleted_at'] || hash[:deleted_at],
      disabled_at: hash['disabled_at'] || hash[:disabled_at]
    )
  end
end

# 类功能：基于文件的内存存储实现
# 使用方法：传入配置选项创建实例，支持创建、更新、删除、查询内存记录
class FileMemoryStore
  # 方法功能：初始化文件内存存储
  # 参数：options - 存储选项哈希
  # 选项：root_dir - 内存文件根目录，config - 内存能力配置，now_iso - 可选时钟函数
  #       id_generator - 可选ID生成器
  # 使用方法：传入配置选项创建存储实例
  # @param options [Hash] the store options
  # @option options [String] :root_dir the root directory for memory files
  # @option options [Hash] :config the memory capability config
  # @option options [Proc] :now_iso optional clock function
  # @option options [Proc] :id_generator optional ID generator
  def initialize(options)
    @root_dir = options[:root_dir]
    @config = options[:config]
    @now_iso = options[:now_iso] || -> { Time.now.utc.strftime('%FT%TZ') }
    @id_generator = options[:id_generator] || lambda {
      "mem_#{Time.now.to_i.to_s(36)}_#{rand(36**6).to_s(36)[0, 6]}"
    }
    @last_injected_ids = []
  end

  # 方法功能：创建新的内存记录
  # 参数：input - 创建输入哈希
  # 返回值：创建的内存记录对象
  # 使用方法：传入包含内容、作用域等信息的哈希，创建并保存记录
  # @param input [Hash] the creation input
  # @return [MemoryRecord] the created record
  def create(input)
    FileUtils.mkdir_p(@root_dir)
    id = @id_generator.call
    @now_iso.call

    record = MemoryStore.create_record(
      id: id,
      content: input[:content],
      scope: input[:scope] || 'workspace',
      workspace: input[:workspace],
      project: input[:project],
      source_thread_id: input[:source_thread_id],
      source_turn_id: input[:source_turn_id],
      tags: input[:tags] || [],
      confidence: input[:confidence] || 1.0
    )
    write(record)
    record
  end

  # 方法功能：更新内存记录
  # 参数：id - 记录ID，patch - 更新补丁哈希
  # 返回值：更新后的内存记录对象
  # 使用方法：传入记录ID和更新内容，更新并保存记录
  # @param id [String] the record ID
  # @param patch [Hash] the updates
  # @return [MemoryRecord] the updated record
  def update(id, patch)
    current = must_get(id)
    now = @now_iso.call

    next_record = current.dup
    next_record.content = patch[:content] if patch.key?(:content)
    next_record.tags = patch[:tags] if patch.key?(:tags)
    next_record.confidence = patch[:confidence] if patch.key?(:confidence)
    if patch[:disabled] == true
      next_record.disabled_at ||= now
    elsif patch[:disabled] == false
      next_record.disabled_at = nil
    end
    next_record.updated_at = now

    write(next_record)
    next_record
  end

  # 方法功能：软删除内存记录
  # 参数：id - 记录ID
  # 返回值：删除后的内存记录对象（标记删除时间）
  # 使用方法：传入记录ID，软删除记录（设置deleted_at时间戳）
  # @param id [String] the record ID
  # @return [MemoryRecord] the deleted record
  def delete(id)
    current = must_get(id)
    now = @now_iso.call

    next_record = current.dup
    next_record.deleted_at ||= now
    next_record.updated_at = now

    write(next_record)
    next_record
  end

  # 方法功能：列出内存记录
  # 参数：filter - 可选过滤条件哈希
  # 选项：workspace - 按工作区过滤，include_deleted - 包含已删除记录
  # 返回值：内存记录数组（按更新时间倒序）
  # 使用方法：传入过滤条件，返回匹配的内存记录列表
  # @param filter [Hash] optional filters
  # @option filter [String] :workspace filter by workspace
  # @option filter [Boolean] :include_deleted include deleted records
  # @return [Array<MemoryRecord>] the records
  def list(filter = {})
    records = read_all
    records
      .select { |record| filter[:include_deleted] || record.deleted_at.nil? }
      .select { |record| in_scope?(record, filter[:workspace]) }
      .sort_by { |record| record.updated_at || '' }
      .reverse
  end

  # 方法功能：检索匹配查询的内存记录
  # 参数：input - 检索输入哈希
  # 选项：query - 搜索查询，workspace - 工作区过滤，limit - 最大结果数
  # 返回值：匹配的内存记录数组（按相关性排序）
  # 使用方法：传入查询参数，返回相关性最高的内存记录
  # @param input [Hash] the retrieval input
  # @option input [String] :query the search query
  # @option input [String] :workspace filter by workspace
  # @option input [Integer] :limit maximum results
  # @return [Array<MemoryRecord>] the matching records
  def retrieve(input)
    return [] unless @config[:enabled]

    active = list(workspace: input[:workspace])
             .reject(&:disabled_at)

    active
      .map { |record| { record: record, score: score_memory(record, input[:query]) } }
      .select { |entry| entry[:score].positive? }
      .sort_by { |entry| [-entry[:score], entry[:record].updated_at || ''] }
      .first(input[:limit])
      .map { |entry| entry[:record] }
  end

  # 方法功能：获取诊断信息
  # 返回值：诊断信息哈希
  # 使用方法：调用返回包含启用状态、根目录、活跃记录数等诊断信息
  # @return [Hash] diagnostics information
  def diagnostics
    records = read_all
    {
      enabled: @config[:enabled],
      root_dir: @root_dir,
      active_count: records.count { |r| r.deleted_at.nil? && r.disabled_at.nil? },
      tombstone_count: records.count { |r| !r.deleted_at.nil? },
      last_injected_ids: @last_injected_ids.dup
    }
  end

  # 方法功能：设置最后注入的ID列表
  # 参数：ids - ID数组
  # 使用方法：传入ID数组，记录最后注入的内存ID
  # @param ids [Array<String>] the IDs
  def set_last_injected(ids)
    @last_injected_ids = ids.dup
  end

  private

  # 方法功能：获取指定ID的记录（必须存在）
  # 参数：id - 记录ID
  # 返回值：内存记录对象
  # 异常：找不到记录时抛出RuntimeError
  # 使用方法：传入记录ID，返回记录或抛出异常
  # @param id [String] the record ID
  # @return [MemoryRecord] the record
  # @raise [RuntimeError] if not found
  def must_get(id)
    record = read_all.find { |r| r.id == id }
    raise "memory not found: #{id}" unless record

    record
  end

  # 方法功能：读取所有内存记录
  # 返回值：所有内存记录数组
  # 使用方法：调用读取并解析所有JSON文件，返回记录列表
  # @return [Array<MemoryRecord>] all records
  def read_all
    FileUtils.mkdir_p(@root_dir)
    entries = Dir.entries(@root_dir).select { |e| e.end_with?('.json') }
    entries.filter_map do |entry|
      text = File.read(File.join(@root_dir, entry))
      MemoryStore.from_hash(JSON.parse(text))
    rescue StandardError
      nil
    end
  end

  # 方法功能：写入内存记录到文件
  # 参数：record - 内存记录对象
  # 使用方法：传入记录对象，将记录序列化为JSON并写入文件
  # @param record [MemoryRecord] the record to write
  def write(record)
    FileUtils.mkdir_p(@root_dir)
    File.write(
      File.join(@root_dir, "#{record.id}.json"),
      JSON.pretty_generate(MemoryStore.to_hash(record))
    )
  end

  # 方法功能：检查记录是否在指定作用域内
  # 参数：record - 内存记录对象，workspace - 工作区
  # 返回值：布尔值表示记录是否在作用域内
  # 使用方法：传入记录和工作区，检查记录是否可见
  # @param record [MemoryRecord] the record
  # @param workspace [String, nil] the workspace
  # @return [Boolean] whether the record is in scope
  def in_scope?(record, workspace)
    return true if record.scope == 'user'
    return true if workspace.nil?
    return record.workspace == workspace if record.scope == 'workspace'

    true
  end

  # 方法功能：计算内存记录与查询的相关性分数
  # 参数：record - 内存记录对象，query - 查询字符串
  # 返回值：相关性分数浮点数
  # 使用方法：传入记录和查询，基于关键词匹配计算相关性
  # @param record [MemoryRecord] the record
  # @param query [String] the query
  # @return [Float] the score
  def score_memory(record, query)
    words = query.downcase.split(/[^a-z0-9_]+/).select { |w| w.length > 2 }.to_set
    score = 0
    text = "#{record.content} #{record.tags.join(' ')}".downcase
    words.each do |word|
      score += 1 if text.include?(word)
    end
    score * record.confidence
  end
end
