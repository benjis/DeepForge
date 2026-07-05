# frozen_string_literal: true

require 'digest'
require 'json'

# 文件用途：工具目录指纹计算，用于缓存失效检测
# 使用方法：使用ToolCatalogFingerprint模块计算工具列表的指纹，检测工具变更

# 模块功能：工具目录指纹计算，提供工具规格规范化和哈希计算
# 使用方法：调用build方法计算工具列表的指纹信息
module ToolCatalogFingerprint
  module_function

  # 方法功能：构建工具目录指纹
  # 参数：tools - 工具规格数组
  # 返回值：包含指纹、工具数量、工具名称和工具哈希的哈希
  # 使用方法：传入工具列表，返回完整的指纹信息
  # @param tools [Array<Hash>] the tool specifications
  # @return [Hash] fingerprint information with :fingerprint, :tool_count, :tool_names, :tool_hashes
  def build(tools)
    canonical_tools = normalize_tool_specs(tools)
    {
      fingerprint: hash_object(canonical_tools),
      tool_count: canonical_tools.length,
      tool_names: canonical_tools.map { |tool| tool[:name] },
      tool_hashes: canonical_tools.to_h { |tool| [tool[:name], hash_object(tool)] }
    }
  end

  # 方法功能：规范化工具规格列表
  # 参数：tools - 工具规格数组
  # 返回值：规范化并排序后的工具规格数组
  # 使用方法：传入工具列表，返回按名称排序的规范化版本
  # @param tools [Array<Hash>] the tool specs to normalize
  # @return [Array<Hash>] normalized and sorted tool specs
  def normalize_tool_specs(tools)
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

  # 方法功能：将对象规范化为模式
  # 参数：value - 要规范化的对象
  # 返回值：规范化后的模式哈希，非哈希返回空哈希
  # 使用方法：传入对象，返回规范化后的模式
  # @param value [Object] the value to canonicalize as a schema
  # @return [Hash] canonicalized schema
  def canonicalize_schema(value)
    canonical = canonicalize(value)
    canonical.is_a?(Hash) ? canonical : {}
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

  # 方法功能：计算对象的SHA256哈希
  # 参数：value - 要哈希的对象
  # 返回值：截断为16个字符的SHA256哈希字符串
  # 使用方法：传入任意对象，返回其哈希值
  # @param value [Object] the value to hash
  # @return [String] SHA256 hash truncated to 16 characters
  def hash_object(value)
    Digest::SHA256.hexdigest(JSON.generate(value))[0, 16]
  end
end
