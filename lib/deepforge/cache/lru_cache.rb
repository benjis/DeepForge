# frozen_string_literal: true

# 文件用途：有界LRU缓存，实现最近最少使用淘汰策略
# 使用方法：创建LruCache实例，使用get/set/delete等方法操作缓存

# 类功能：有界LRU缓存，支持最大容量限制和自动淘汰
# 使用方法：set操作提升项到最新位置，get操作提升并返回值，缓存满时淘汰最旧项
class LruCache
  # 属性功能：获取缓存最大容量
  # @return [Integer] the maximum number of entries
  attr_reader :limit

  # 方法功能：获取当前缓存条目数
  # 返回值：当前条目数整数
  # 使用方法：调用返回缓存中的条目数量
  # @return [Integer] the current number of entries
  def size
    @entries.size
  end

  # 方法功能：初始化LRU缓存
  # 参数：limit - 最大容量（必须大于0）
  # 异常：容量不大于0时抛出ArgumentError
  # 使用方法：传入正整数容量创建缓存实例
  # @param limit [Integer] maximum number of entries (must be > 0)
  def initialize(limit)
    raise ArgumentError, 'LruCache requires limit > 0' unless limit.is_a?(Integer) && limit.positive?

    @limit = limit
    @entries = {}
  end

  # 方法功能：检查键是否存在
  # 参数：key - 要检查的键
  # 返回值：布尔值表示键是否存在
  # 使用方法：传入键，检查是否在缓存中
  # @param key [Object] the key to check
  # @return [Boolean] whether the key exists in the cache
  def has?(key)
    @entries.key?(key)
  end

  # 方法功能：获取缓存值
  # 参数：key - 要查找的键
  # 返回值：存储的值或nil（未找到时）
  # 使用方法：传入键，返回对应的值并提升到最新位置
  # @param key [Object] the key to look up
  # @return [Object, nil] the stored value or nil if not found
  def get(key)
    return nil unless @entries.key?(key)

    value = @entries.delete(key)
    @entries[key] = value
    value
  end

  # 方法功能：设置缓存值
  # 参数：key - 要设置的键，value - 要存储的值
  # 返回值：被淘汰的值（如果有），否则nil
  # 使用方法：传入键值对，设置缓存，缓存满时返回被淘汰的值
  # @param key [Object] the key to set
  # @param value [Object] the value to store
  # @return [Object, nil] the evicted value if any, or nil
  def set(key, value)
    evicted = nil
    if @entries.key?(key)
      @entries.delete(key)
    elsif @entries.size >= @limit
      oldest_key = @entries.keys.first
      if oldest_key
        evicted = @entries[oldest_key]
        @entries.delete(oldest_key)
      end
    end
    @entries[key] = value
    evicted
  end

  # 方法功能：删除缓存条目
  # 参数：key - 要删除的键
  # 返回值：布尔值表示键是否存在
  # 使用方法：传入键，删除对应的缓存条目
  # @param key [Object] the key to delete
  # @return [Boolean] whether the key was present
  def delete(key)
    return false unless @entries.key?(key)

    @entries.delete(key)
    true
  end

  # 方法功能：清空缓存
  # 使用方法：调用清空所有缓存条目
  def clear
    @entries.clear
  end

  # 方法功能：获取所有缓存键
  # 返回值：所有键的数组
  # 使用方法：调用返回缓存中所有键的列表
  # @return [Array<Object>] all keys in the cache
  def keys
    @entries.keys
  end

  # 方法功能：获取所有缓存值
  # 返回值：所有值的数组
  # 使用方法：调用返回缓存中所有值的列表
  # @return [Array<Object>] all values in the cache
  def values
    @entries.values
  end
end
