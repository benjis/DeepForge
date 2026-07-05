# frozen_string_literal: true

# 文件用途：时钟端口，提供时间获取功能
# 使用方法：继承Clock类并实现now、now_iso、now_ms方法，测试时可注入确定性时钟

module DeepForge
  module Ports
    # @abstract Subclass and implement {#now}, {#now_iso}, {#now_ms}
    # Port for time. The default implementation uses `Time.now`;
    # tests can inject a deterministic clock to reason about expiry windows.

    # 类功能：时钟端口基类，定义时间获取接口
    class Clock
      # 方法功能：获取当前时间对象
      # 返回值：Time对象
      # 使用方法：调用返回当前系统时间
      # @return [Time]
      def now
        raise NotImplementedError
      end

      # 方法功能：获取ISO 8601格式的当前时间字符串
      # 返回值：ISO 8601时间戳字符串
      # 使用方法：调用返回UTC格式的ISO 8601时间字符串
      # @return [String] ISO 8601 timestamp
      def now_iso
        raise NotImplementedError
      end

      # 方法功能：获取当前时间的毫秒级时间戳
      # 返回值：自纪元以来的毫秒数
      # 使用方法：调用返回毫秒级Unix时间戳
      # @return [Integer] milliseconds since epoch
      def now_ms
        raise NotImplementedError
      end
    end

    # 类功能：系统时钟实现，使用真实系统时间
    class SystemClock < Clock
      # 方法功能：获取当前系统时间
      # 返回值：Time对象
      # 使用方法：调用返回当前系统时间
      # @return [Time]
      def now
        Time.now
      end

      # 方法功能：获取UTC格式的ISO 8601时间字符串
      # 返回值：ISO 8601时间戳字符串
      # 使用方法：调用返回UTC格式的ISO 8601时间字符串
      # @return [String]
      def now_iso
        Time.now.utc.strftime('%FT%TZ')
      end

      # 方法功能：获取当前时间的毫秒级时间戳
      # 返回值：自纪元以来的毫秒数
      # 使用方法：调用返回毫秒级Unix时间戳
      # @return [Integer]
      def now_ms
        (Time.now.to_f * 1000).to_i
      end
    end
  end
end
