# frozen_string_literal: true

require 'json'

# 文件用途：前缀波动性检测器，用于扫描不可变提示缓存前缀中的易变内容
# 使用方法：使用PrefixVolatility模块检测UUID、哈希、ISO日期、JWT等易变令牌

# 模块功能：前缀波动性检测，使用结构化令牌解析避免正则表达式的误报
# 使用方法：调用detect_volatile_prefix_content扫描前缀，返回易变内容发现列表
module PrefixVolatility
  module_function

  # 常量功能：哈希长度常量（MD5、SHA1、SHA256）
  HASH_LENGTHS = [32, 40, 64].freeze
  # 常量功能：UUID段长度常量（8-4-4-4-12格式）
  UUID_SEGMENT_LENGTHS = [8, 4, 4, 4, 12].freeze
  # 常量功能：边界标点字符
  BOUNDARY_PUNCTUATION = '.,;:!?()[]{}<>"\'`'

  # 方法功能：检测前缀中的易变内容
  # 参数：prefix - 要扫描的不可变前缀对象
  # 返回值：发现列表数组，包含字段、类型、令牌和项ID
  # 使用方法：传入前缀对象，返回所有易变内容的发现
  # @param prefix [ImmutablePrefix] the prefix to scan
  # @return [Array<Hash>] findings with :field, :kind, :token, :item_id
  def detect_volatile_prefix_content(prefix)
    findings = []
    findings.concat(detect_volatile_tokens('systemPrompt', prefix.system_prompt))
    prefix.few_shots.each do |item|
      findings.concat(detect_volatile_few_shot_item(item))
    end
    findings
  end

  # 方法功能：获取少样本项的文本内容
  # 参数：item - 轮次项哈希
  # 返回值：项的文本内容字符串，或nil（不支持的类型）
  # 使用方法：传入轮次项，提取其文本内容用于波动性检测
  # @param item [Hash] the turn item
  # @return [String, nil] the text content of the item
  def few_shot_text(item)
    case item[:kind]
    when 'user_message', 'assistant_text', 'assistant_reasoning'
      item[:text]
    when 'tool_call'
      "#{item[:tool_name]} #{stable_stringify(item[:arguments])}"
    when 'tool_result'
      "#{item[:tool_name]} #{stable_stringify(item[:output])}"
    when 'approval'
      "#{item[:tool_name]} #{item[:summary]}"
    when 'user_input'
      item[:prompt]
    when 'compaction'
      item[:summary]
    when 'review'
      "#{item[:title]} #{item[:review_text] || ''} #{stable_stringify(item[:output] || {})}"
    when 'error'
      item[:message]
    end
  end

  # 方法功能：检测少样本项中的易变内容
  # 参数：item - 轮次项哈希
  # 返回值：该项的易变内容发现数组
  # 使用方法：传入轮次项，返回该项中的易变令牌
  # @param item [Hash] the turn item
  # @return [Array<Hash>] findings for this item
  def detect_volatile_few_shot_item(item)
    text = few_shot_text(item)
    return [] unless text

    detect_volatile_tokens('fewShots', text, item[:id])
  end

  # 方法功能：检测指定内容中的易变令牌
  # 参数：field - 字段名称，content - 要扫描的内容，item_id - 可选项ID
  # 返回值：易变令牌发现数组
  # 使用方法：传入字段名和内容，返回所有易变令牌的发现
  # @param field [String] the field name
  # @param content [String] the content to scan
  # @param item_id [String, nil] optional item ID
  # @return [Array<Hash>] findings
  def detect_volatile_tokens(field, content, item_id = nil)
    findings = []
    split_tokens(content).each do |raw_token|
      token = strip_boundary_punctuation(raw_token)
      next unless token

      kind = volatile_token_kind(token)
      next unless kind

      finding = { field: field, kind: kind, token: token }
      finding[:item_id] = item_id if item_id
      findings << finding
    end
    findings
  end

  # 方法功能：分类令牌的波动性类型
  # 参数：token - 要分类的令牌字符串
  # 返回值：波动性类型字符串（'uuid'、'iso8601'、'hex_hash'、'jwt'）或nil
  # 使用方法：传入令牌，返回其波动性分类
  # @param token [String] the token to classify
  # @return [String, nil] the volatility kind
  def volatile_token_kind(token)
    return 'uuid' if canonical_uuid?(token)
    return 'iso8601' if iso8601?(token)
    return 'hex_hash' if hex_hash?(token)
    return 'jwt' if jwt?(token)

    nil
  end

  # 方法功能：将内容分割为令牌
  # 参数：content - 要分割的内容字符串
  # 返回值：令牌数组
  # 使用方法：传入内容字符串，按空白字符分割为令牌
  # @param content [String] the content to split
  # @return [Array<String>] tokens
  def split_tokens(content)
    tokens = []
    current = ''
    content.each_char do |char|
      if whitespace?(char)
        tokens << current unless current.empty?
        current = ''
      else
        current += char
      end
    end
    tokens << current unless current.empty?
    tokens
  end

  # 方法功能：去除令牌的边界标点
  # 参数：token - 要处理的令牌字符串
  # 返回值：去除边界标点后的令牌
  # 使用方法：传入令牌，返回去除首尾标点后的版本
  # @param token [String] the token to strip
  # @return [String] stripped token
  def strip_boundary_punctuation(token)
    start_idx = 0
    end_idx = token.length
    start_idx += 1 while start_idx < end_idx && BOUNDARY_PUNCTUATION.include?(token[start_idx])
    end_idx -= 1 while end_idx > start_idx && BOUNDARY_PUNCTUATION.include?(token[end_idx - 1])
    token[start_idx...end_idx]
  end

  # 方法功能：检查令牌是否为规范UUID
  # 参数：token - 要检查的令牌字符串
  # 返回值：布尔值表示是否为规范UUID格式
  # 使用方法：传入令牌，检查是否符合8-4-4-4-12格式的UUID
  # @param token [String] the token to check
  # @return [Boolean] whether it's a canonical UUID
  def canonical_uuid?(token)
    return false unless token.length == 36

    parts = token.split('-')
    return false unless parts.length == 5

    parts.each_with_index do |part, index|
      return false unless part.length == UUID_SEGMENT_LENGTHS[index]
      return false unless hex_string?(part)
    end
    true
  end

  # 方法功能：检查令牌是否为ISO 8601日期
  # 参数：token - 要检查的令牌字符串
  # 返回值：布尔值表示是否为ISO 8601日期格式
  # 使用方法：传入令牌，检查是否符合YYYY-MM-DD格式的日期
  # @param token [String] the token to check
  # @return [Boolean] whether it's an ISO 8601 date
  def iso8601?(token)
    return false if token.length < 10
    return false if token[4] != '-' || token[7] != '-'

    year = parse_fixed_int(token[0, 4])
    month = parse_fixed_int(token[5, 2])
    day = parse_fixed_int(token[8, 2])
    return false if year.nil? || month.nil? || day.nil?

    if token.length > 10
      separator = token[10]
      return false unless ['T', ' '].include?(separator)
    end

    parsed = begin
      Time.parse(token)
    rescue StandardError
      nil
    end
    return false unless parsed

    parsed.year == year && parsed.month == month && parsed.day == day
  end

  # 方法功能：检查令牌是否为十六进制哈希
  # 参数：token - 要检查的令牌字符串
  # 返回值：布尔值表示是否为十六进制哈希
  # 使用方法：传入令牌，检查是否为32、40或64字符的十六进制字符串
  # @param token [String] the token to check
  # @return [Boolean] whether it's a hex hash
  def hex_hash?(token)
    HASH_LENGTHS.include?(token.length) && hex_string?(token)
  end

  # 方法功能：检查令牌是否为JWT
  # 参数：token - 要检查的令牌字符串
  # 返回值：布尔值表示是否为JWT格式
  # 使用方法：传入令牌，检查是否为三部分Base64编码的JWT
  # @param token [String] the token to check
  # @return [Boolean] whether it's a JWT
  def jwt?(token)
    parts = token.split('.')
    return false unless parts.length == 3
    return false unless parts.all? { |part| !part.empty? && base64_url_string?(part) }

    header = decode_base64_url_json(parts[0])
    payload = decode_base64_url_json(parts[1])
    json_object?(header) && json_object?(payload)
  end

  # 方法功能：检查字符是否为空白字符
  # 参数：char - 要检查的字符
  # 返回值：布尔值表示是否为空白字符
  # 使用方法：传入字符，检查是否为空格、制表符等空白字符
  # @param char [String] the character to check
  # @return [Boolean] whether it's whitespace
  def whitespace?(char)
    char.match?(/\s/)
  end

  # 方法功能：解析固定长度整数
  # 参数：value - 要解析的字符串
  # 返回值：解析后的整数，或nil（非数字字符串）
  # 使用方法：传入数字字符串，返回解析后的整数
  # @param value [String] the string to parse as integer
  # @return [Integer, nil] the parsed integer
  def parse_fixed_int(value)
    return nil unless digit_string?(value)

    value.to_i
  end

  # 方法功能：检查字符串是否只包含数字
  # 参数：value - 要检查的字符串
  # 返回值：布尔值表示是否只包含数字
  # 使用方法：传入字符串，检查是否为纯数字
  # @param value [String] the string to check
  # @return [Boolean] whether it contains only digits
  def digit_string?(value)
    !value.empty? && value.match?(/\A\d+\z/)
  end

  # 方法功能：检查字符串是否只包含十六进制字符
  # 参数：value - 要检查的字符串
  # 返回值：布尔值表示是否只包含十六进制字符
  # 使用方法：传入字符串，检查是否为纯十六进制
  # @param value [String] the string to check
  # @return [Boolean] whether it contains only hex characters
  def hex_string?(value)
    !value.empty? && value.match?(/\A[0-9a-fA-F]+\z/)
  end

  # 方法功能：检查字符串是否为Base64 URL编码字符串
  # 参数：value - 要检查的字符串
  # 返回值：布尔值表示是否为Base64 URL字符串
  # 使用方法：传入字符串，检查是否符合Base64 URL编码格式
  # @param value [String] the string to check
  # @return [Boolean] whether it's a base64 URL string
  def base64_url_string?(value)
    value.match?(/\A[A-Za-z0-9_\-=]+\z/)
  end

  # 方法功能：解码Base64 URL编码的JSON
  # 参数：value - Base64 URL编码的字符串
  # 返回值：解码后的JSON对象，或nil（解码失败）
  # 使用方法：传入Base64 URL编码字符串，返回解码后的JSON对象
  # @param value [String] the base64 URL encoded string to decode
  # @return [Object, nil] the decoded JSON object
  def decode_base64_url_json(value)
    decoded = Base64.urlsafe_decode64(value + ('=' * ((4 - (value.length % 4)) % 4)))
    JSON.parse(decoded)
  rescue StandardError
    nil
  end

  # 方法功能：检查值是否为JSON对象
  # 参数：value - 要检查的值
  # 返回值：布尔值表示是否为Hash类型
  # 使用方法：传入值，检查是否为JSON对象（Hash）
  # @param value [Object] the value to check
  # @return [Boolean] whether it's a JSON object
  def json_object?(value)
    value.is_a?(Hash)
  end

  # 方法功能：稳定序列化值为JSON字符串
  # 参数：value - 要序列化的值
  # 返回值：稳定的JSON字符串
  # 使用方法：传入值，返回键排序后的稳定JSON字符串
  # @param value [Object] the value to stringify
  # @return [String] stable JSON string
  def stable_stringify(value)
    JSON.generate(stable_shape(value))
  rescue StandardError
    value.to_s
  end

  # 方法功能：创建稳定的值形状（递归排序哈希键）
  # 参数：value - 要处理的值
  # 返回值：稳定形状的值，哈希键已排序
  # 使用方法：传入值，返回递归排序键后的稳定版本
  # @param value [Object] the value to shape
  # @return [Object] stable shape with sorted keys
  def stable_shape(value)
    case value
    when Array
      value.map { |v| stable_shape(v) }
    when Hash
      value.each_with_object({}) { |(k, v), out| out[k] = stable_shape(v) }
           .sort.to_h
    else
      value
    end
  end
end
