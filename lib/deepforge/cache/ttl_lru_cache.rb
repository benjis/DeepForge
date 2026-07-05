# frozen_string_literal: true

require_relative 'lru_cache'

# 文件用途：带TTL的LRU缓存，同时支持过期时间和LRU淘汰策略
# 使用方法：创建TtlLruCache实例，使用get/set/delete等方法操作缓存，支持自动过期

# 类功能：带TTL的LRU缓存，结合时间过期和最近最少使用淘汰
# 使用方法：get返回nil表示未命中或已过期，缓存满时可能淘汰仍有效的条目
class TtlLruCache
  # 方法功能：获取当前缓存条目数
  # 返回值：当前条目数整数
  # 使用方法：调用返回缓存中的条目数量
  # @return [Integer] the current number of entries
  def size
    @cache.size
  end

  # 方法功能：初始化TTL LRU缓存
  # 参数：options - 配置选项哈希
  # 选项：limit - 最大容量（必须大于0），ttl_ms - 过期时间毫秒数（必须大于0）
  #       now - 可选时钟函数（默认使用Time.now.to_i * 1000）
  # 使用方法：传入配置选项创建缓存实例
  # @param options [Hash] configuration options
  # @option options [Integer] :limit maximum number of entries (must be > 0)
  # @option options [Integer] :ttl_ms time-to-live in milliseconds (must be > 0)
  # @option options [Proc] :now optional clock function (defaults to Time.now.to_i * 1000)
  def initialize(options)
    limit = options.fetch(:limit)
    ttl_ms = options.fetch(:ttl_ms)

    raise ArgumentError, 'TtlLruCache requires ttlMs > 0' unless ttl_ms.is_a?(Integer) && ttl_ms.positive?

    @cache = LruCache.new(limit)
    @ttl_ms = ttl_ms
    @now = options.fetch(:now, -> { (Time.now.to_f * 1000).to_i })
  end

  # 方法功能：检查键是否存在且未过期
  # 参数：key - 要检查的键
  # 返回值：布尔值表示键是否存在且未过期
  # 使用方法：传入键，检查是否在缓存中且未过期
  # @param key [Object] the key to check
  # @return [Boolean] whether the key exists and is not expired
  def has?(key)
    !get(key).nil?
  end

  # 方法功能：获取缓存值（自动处理过期）
  # 参数：key - 要查找的键
  # 返回值：存储的值或nil（未找到或已过期）
  # 使用方法：传入键，返回值并提升到最新位置，过期条目自动删除
  # @param key [Object] the key to look up
  # @return [Object, nil] the stored value or nil if not found/expired
  def get(key)
    entry = @cache.get(key)
    return nil unless entry

    if entry[:expires_at] <= @now.call
      @cache.delete(key)
      return nil
    end

    entry[:value]
  end

  # 方法功能：设置缓存值（带TTL）
  # 参数：key - 要设置的键，value - 要存储的值
  # 返回值：被淘汰的值（如果有），否则nil
  # 使用方法：传入键值对，设置缓存并设置过期时间，缓存满时返回被淘汰的值
  # @param key [Object] the key to set
  # @param value [Object] the value to store
  # @return [Object, nil] the evicted value if any, or nil
  def set(key, value)
    expires_at = @now.call + @ttl_ms
    evicted = @cache.set(key, { value: value, expires_at: expires_at })
    evicted&.dig(:value)
  end

  # 方法功能：删除缓存条目
  # 参数：key - 要删除的键
  # 返回值：布尔值表示键是否存在
  # 使用方法：传入键，删除对应的缓存条目
  # @param key [Object] the key to delete
  # @return [Boolean] whether the key was present
  def delete(key)
    @cache.delete(key)
  end

  # 方法功能：清空缓存
  # 使用方法：调用清空所有缓存条目
  def clear
    @cache.clear
  end

  # 方法功能：清理所有过期条目
  # 返回值：被删除的条目数
  # 使用方法：调用遍历所有条目，删除已过期的条目
  # @return [Integer] the number of entries dropped
  def sweep
    now = @now.call
    dropped = 0
    @cache.keys.each do |key|
      entry = @cache.get(key)
      next unless entry

      if entry[:expires_at] <= now
        @cache.delete(key)
        dropped += 1
      end
    end
    dropped
  end
end
