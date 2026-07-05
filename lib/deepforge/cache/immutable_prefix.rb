# frozen_string_literal: true

require 'digest'
require 'json'

# 文件用途：不可变前缀管理，用于提示缓存的指纹计算和验证
# 使用方法：使用ImmutablePrefixBuilder模块创建、修改和验证前缀，支持缓存失效检测

# 结构体功能：不可变前缀数据结构
# 使用方法：包含系统提示、工具、约束、少样本示例、指纹和版本号
ImmutablePrefix = Struct.new(
  :system_prompt,
  :tools,
  :pinned_constraints,
  :few_shots,
  :fingerprint,
  :revision,
  keyword_init: true
)

# 模块功能：不可变前缀构建器，提供前缀创建、修改和验证功能
# 使用方法：使用模块函数创建、修改和验证不可变前缀，支持缓存指纹计算
module ImmutablePrefixBuilder
  module_function

  # 常量功能：生产环境验证标志
  VERIFY_IMMUTABLE_PREFIX_IN_PROD = ENV['DEEPFORGE_VERIFY_IMMUTABLE_PREFIX'] == '1'

  # 方法功能：计算对象的SHA256哈希
  # 参数：value - 要哈希的对象
  # 返回值：截断为16个字符的SHA256哈希字符串
  # 使用方法：传入任意对象，返回其哈希值
  # @param value [Object] the value to hash
  # @return [String] SHA256 hash truncated to 16 characters
  def hash_object(value)
    Digest::SHA256.hexdigest(JSON.generate(value))[0, 16]
  end

  # 方法功能：规范化对象（递归排序哈希键）
  # 参数：value - 要规范化的对象
  # 返回值：规范化后的对象，哈希键已排序
  # 使用方法：传入对象，返回键排序后的规范化版本
  # @param value [Object] the value to canonicalize
  # @return [Object] canonicalized value with sorted keys
  def canonicalize(value)
    case value
    when Array
      value.map { |v| canonicalize(v) }
    when Hash
      value.each_with_object({}) { |(k, v), out| out[k] = canonicalize(v) }
           .sort.to_h
    else
      value
    end
  end

  # 方法功能：将对象规范化为模式（Schema）
  # 参数：value - 要规范化的对象
  # 返回值：规范化后的模式哈希，非哈希返回空哈希
  # 使用方法：传入对象，返回规范化后的模式
  # @param value [Object] the value to canonicalize as a schema
  # @return [Hash] canonicalized schema
  def canonicalize_schema(value)
    canonical = canonicalize(value)
    canonical.is_a?(Hash) ? canonical : {}
  end

  # 方法功能：规范化工具列表
  # 参数：tools - 工具规格数组
  # 返回值：规范化并排序后的工具数组
  # 使用方法：传入工具列表，返回按名称排序的规范化版本
  # @param tools [Array<Hash>] the tools to normalize
  # @return [Array<Hash>] normalized and sorted tools
  def normalize_tools(tools)
    tools
      .map do |tool|
        {
          name: tool[:name] || tool['name'],
          description: tool[:description] || tool['description'],
          input_schema: canonicalize_schema(tool[:input_schema] || tool['inputSchema'] || {})
        }
      end
      .sort_by { |tool| tool[:name] }
  end

  # 方法功能：获取少样本项的缓存形状
  # 参数：item - 轮次项哈希
  # 返回值：用于指纹计算的缓存形状哈希，或nil（不支持的类型）
  # 使用方法：传入轮次项，返回用于缓存指纹计算的简化版本
  # @param item [Hash] the turn item
  # @return [Hash, nil] cache shape for fingerprinting
  def few_shot_cache_shape(item)
    case item[:kind]
    when 'user_message'
      { kind: item[:kind], text: item[:text] }
    when 'assistant_text'
      { kind: item[:kind], text: item[:text] }
    when 'tool_call'
      {
        kind: item[:kind],
        call_id: item[:call_id] || item[:callId],
        tool_name: item[:tool_name] || item[:toolName],
        arguments: canonicalize(item[:arguments])
      }
    when 'tool_result'
      {
        kind: item[:kind],
        call_id: item[:call_id] || item[:callId],
        output: canonicalize(item[:output])
      }
    when 'assistant_reasoning', 'approval', 'user_input', 'compaction', 'error'
      nil
    end
  end

  # 方法功能：构建前缀指纹
  # 参数：input - 前缀组件哈希
  # 返回值：指纹哈希字符串
  # 使用方法：传入系统提示、工具、约束和少样本示例，计算指纹
  # @param input [Hash] the prefix components
  # @return [String] fingerprint hash
  def build_fingerprint(input)
    hash_object({
                  system_prompt: input[:system_prompt],
                  tools: normalize_tools(input[:tools]),
                  pinned: input[:pinned_constraints],
                  fewShots: input[:few_shots].filter_map { |item| few_shot_cache_shape(item) }
                })
  end

  # 方法功能：检查是否应在生产环境验证前缀
  # 返回值：布尔值表示是否应验证
  # 使用方法：调用返回是否启用生产环境验证
  # @return [Boolean] whether to verify immutable prefix in production
  def should_verify?
    ENV['NODE_ENV'] != 'production' || VERIFY_IMMUTABLE_PREFIX_IN_PROD
  end

  # 方法功能：创建新的不可变前缀
  # 参数：input - 可选配置哈希
  # 选项：system_prompt - 系统提示，tools - 工具规格，pinned_constraints - 固定约束，few_shots - 少样本示例
  # 返回值：创建的不可变前缀对象
  # 使用方法：传入配置选项，创建带有指纹和版本号的新前缀
  # @param input [Hash] optional configuration
  # @option input [String] :system_prompt the system prompt
  # @option input [Array<Hash>] :tools tool specifications
  # @option input [Array<String>] :pinned_constraints constraints to preserve
  # @option input [Array<Hash>] :few_shots few-shot examples
  # @return [ImmutablePrefix] the created prefix
  def create(input = {})
    system_prompt = input[:system_prompt] || ''
    tools = normalize_tools(input[:tools] || [])
    pinned_constraints = input[:pinned_constraints] || []
    few_shots = input[:few_shots] || []

    fingerprint = build_fingerprint(
      system_prompt: system_prompt,
      tools: tools,
      pinned_constraints: pinned_constraints,
      few_shots: few_shots
    )

    ImmutablePrefix.new(
      system_prompt: system_prompt,
      tools: tools,
      pinned_constraints: pinned_constraints,
      few_shots: few_shots,
      fingerprint: fingerprint,
      revision: 1
    )
  end

  # 方法功能：修改不可变前缀
  # 参数：prefix - 当前前缀对象，patch - 要更新的字段哈希
  # 返回值：修改后的前缀对象（新对象，原对象不变）
  # 使用方法：传入前缀和更新内容，返回新版本的前缀
  # @param prefix [ImmutablePrefix] the current prefix
  # @param patch [Hash] the fields to update
  # @return [ImmutablePrefix] the mutated prefix
  def mutate(prefix, patch)
    tools = patch[:tools] ? normalize_tools(patch[:tools]) : prefix.tools
    pinned_constraints = patch[:pinned_constraints] || prefix.pinned_constraints
    few_shots = patch[:few_shots] || prefix.few_shots
    system_prompt = patch[:system_prompt] || prefix.system_prompt

    fingerprint = build_fingerprint(
      system_prompt: system_prompt,
      tools: tools,
      pinned_constraints: pinned_constraints,
      few_shots: few_shots
    )

    prefix.dup.tap do |p|
      p.system_prompt = system_prompt
      p.tools = tools
      p.pinned_constraints = pinned_constraints
      p.few_shots = few_shots
      p.fingerprint = fingerprint
      p.revision = prefix.revision + 1
    end
  end

  # 方法功能：设置系统提示
  # 参数：prefix - 要更新的前缀对象，system_prompt - 新的系统提示
  # 返回值：更新后的前缀对象
  # 使用方法：传入前缀和新系统提示，返回更新后的前缀
  # @param prefix [ImmutablePrefix] the prefix to update
  # @param system_prompt [String] the new system prompt
  # @return [ImmutablePrefix] the updated prefix
  def set_system_prompt(prefix, system_prompt)
    mutate(prefix, system_prompt: system_prompt)
  end

  # 方法功能：设置工具列表
  # 参数：prefix - 要更新的前缀对象，tools - 新的工具数组
  # 返回值：更新后的前缀对象
  # 使用方法：传入前缀和新工具列表，返回更新后的前缀
  # @param prefix [ImmutablePrefix] the prefix to update
  # @param tools [Array<Hash>] the new tools
  # @return [ImmutablePrefix] the updated prefix
  def set_tools(prefix, tools)
    mutate(prefix, tools: tools)
  end

  # 方法功能：设置固定约束
  # 参数：prefix - 要更新的前缀对象，pinned - 新的固定约束数组
  # 返回值：更新后的前缀对象
  # 使用方法：传入前缀和新固定约束，返回更新后的前缀
  # @param prefix [ImmutablePrefix] the prefix to update
  # @param pinned [Array<String>] the new pinned constraints
  # @return [ImmutablePrefix] the updated prefix
  def set_pinned_constraints(prefix, pinned)
    mutate(prefix, pinned_constraints: pinned)
  end

  # 方法功能：设置少样本示例
  # 参数：prefix - 要更新的前缀对象，few_shots - 新的少样本示例数组
  # 返回值：更新后的前缀对象
  # 使用方法：传入前缀和新少样本示例，返回更新后的前缀
  # @param prefix [ImmutablePrefix] the prefix to update
  # @param few_shots [Array<Hash>] the new few-shot examples
  # @return [ImmutablePrefix] the updated prefix
  def set_few_shots(prefix, few_shots)
    mutate(prefix, few_shots: few_shots)
  end

  # 方法功能：验证前缀指纹是否匹配
  # 参数：prefix - 要验证的前缀对象
  # 返回值：验证后的指纹字符串
  # 异常：检测到指纹漂移时抛出RuntimeError
  # 使用方法：传入前缀对象，验证指纹完整性
  # @param prefix [ImmutablePrefix] the prefix to verify
  # @return [String] the verified fingerprint
  # @raise [RuntimeError] if fingerprint drift detected
  def verify(prefix)
    expected = build_fingerprint(prefix)
    unless expected == prefix.fingerprint
      raise "immutable prefix fingerprint drift: expected #{prefix.fingerprint}, actual #{expected}"
    end

    expected
  end

  # 方法功能：描述指纹漂移信息
  # 参数：before - 原始前缀对象，after - 新前缀对象
  # 返回值：包含漂移布尔值和变更字段数组的哈希
  # 使用方法：传入两个前缀对象，比较并返回变更详情
  # @param before [ImmutablePrefix] the original prefix
  # @param after [ImmutablePrefix] the new prefix
  # @return [Hash] drift information with :drift boolean and :changed_fields array
  def describe_fingerprint_drift(before, after)
    changed = []
    changed << 'systemPrompt' if before.system_prompt != after.system_prompt
    changed << 'tools' if hash_object(normalize_tools(before.tools)) != hash_object(normalize_tools(after.tools))
    changed << 'pinnedConstraints' if hash_object(before.pinned_constraints) != hash_object(after.pinned_constraints)
    before_shots = before.few_shots.filter_map { |item| few_shot_cache_shape(item) }
    after_shots = after.few_shots.filter_map { |item| few_shot_cache_shape(item) }
    changed << 'fewShots' if hash_object(before_shots) != hash_object(after_shots)
    { drift: !changed.empty?, changed_fields: changed }
  end
end
