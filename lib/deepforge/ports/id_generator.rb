# frozen_string_literal: true

require 'securerandom'

# 文件用途：ID生成器端口，提供唯一标识符生成功能
# 使用方法：继承IdGenerator类并实现next方法，可选择随机或顺序生成方式

module DeepForge
  module Ports
    # @abstract Subclass and implement {#next}
    # Port for ids. Keeping id allocation behind a tiny interface makes
    # services deterministic in tests and avoids scattering random suffix
    # details through the application layer.

    # 类功能：ID生成器基类，定义ID生成接口
    class IdGenerator
      # 方法功能：生成下一个带前缀的ID
      # 参数：prefix - ID前缀字符串
      # 返回值：生成的ID字符串
      # 使用方法：传入前缀，返回格式为"前缀_随机后缀"的ID
      # @param prefix [String]
      # @return [String]
      def next(prefix)
        raise NotImplementedError
      end
    end

    # 类功能：随机ID生成器，使用随机后缀生成唯一ID
    class RandomIdGenerator < IdGenerator
      # 方法功能：初始化随机ID生成器
      # 参数：random - 可选的随机数生成器，默认使用SecureRandom
      # 使用方法：创建实例，可传入自定义随机数生成器
      # @param random [Proc] callable returning a Float in [0,1)
      def initialize(random: -> { SecureRandom.random_number })
        @random = random
      end

      # 方法功能：生成带前缀的随机ID
      # 参数：prefix - ID前缀字符串
      # 返回值：格式为"前缀_10位随机字符串"的ID
      # 使用方法：传入前缀，返回随机生成的唯一ID
      # @param prefix [String]
      # @return [String]
      def next(prefix)
        val = @random.call
        int_val = val.is_a?(Float) ? (val * (2**48)).to_i : val
        "#{prefix}_#{int_val.to_s(36)[0, 10]}"
      end
    end

    # 类功能：顺序ID生成器，用于测试的确定性ID生成
    class SequentialIdGenerator < IdGenerator
      # 方法功能：初始化顺序ID生成器
      # 使用方法：创建实例，序号从0开始
      def initialize
        @next_seq = 0
      end

      # 方法功能：生成带前缀的顺序ID
      # 参数：prefix - ID前缀字符串
      # 返回值：格式为"前缀_序号"的ID，序号递增
      # 使用方法：传入前缀，返回顺序递增的唯一ID
      # @param prefix [String]
      # @return [String]
      def next(prefix)
        @next_seq += 1
        "#{prefix}_#{@next_seq}"
      end
    end
  end
end
