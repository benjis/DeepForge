# frozen_string_literal: true

# 文件用途：模型上下文配置文件和阈值管理
# 使用方法：通过 ModelContextProfile 模块的类方法调用
# 管理不同模型的上下文窗口、压缩阈值、输入输出模态等配置

# 模块功能：模型上下文配置文件和阈值
# 定义模型的能力特征，包括上下文窗口大小、压缩阈值、输入输出模态等
module DeepForge
  module Loop
    module ModelContextProfile
      module_function

      # 默认上下文阈值配置
      DEFAULT_CONTEXT_THRESHOLDS = {
        soft_threshold: 16_000,
        hard_threshold: 24_000
      }.freeze

      # DeepSeek V4 上下文窗口 token 数
      DEEPSEEK_V4_CONTEXT_WINDOW_TOKENS = 1_000_000
      # DeepSeek V4 软阈值比例
      DEEPSEEK_V4_SOFT_THRESHOLD_RATIO = 0.98
      # DeepSeek V4 硬阈值比例
      DEEPSEEK_V4_HARD_THRESHOLD_RATIO = 0.99

      # 默认输入模态
      DEFAULT_MODEL_INPUT_MODALITIES = ['text'].freeze
      # 默认输出模态
      DEFAULT_MODEL_OUTPUT_MODALITIES = ['text'].freeze
      # 默认消息部分类型
      DEFAULT_MODEL_MESSAGE_PARTS = ['text'].freeze

      # 有效的输入模态
      VALID_INPUT_MODALITIES = %w[text image].freeze
      # 有效的输出模态
      VALID_OUTPUT_MODALITIES = %w[text image].freeze
      # 有效的消息部分类型
      VALID_MESSAGE_PARTS = %w[text image_url input_image].freeze

      # 创建 DeepSeek V4 模型配置文件
      def self.deepseek_v4_profile(id, aliases)
        {
          id: id,
          aliases: aliases,
          context_window_tokens: DEEPSEEK_V4_CONTEXT_WINDOW_TOKENS,
          soft_threshold_ratio: DEEPSEEK_V4_SOFT_THRESHOLD_RATIO,
          hard_threshold_ratio: DEEPSEEK_V4_HARD_THRESHOLD_RATIO,
          input_modalities: DEFAULT_MODEL_INPUT_MODALITIES,
          output_modalities: DEFAULT_MODEL_OUTPUT_MODALITIES,
          message_parts: DEFAULT_MODEL_MESSAGE_PARTS
        }
      end

      # 预定义的模型上下文配置文件列表
      MODEL_CONTEXT_PROFILES = [
        deepseek_v4_profile('deepseek-v4-pro', ['deepseek-v4-pro']),
        deepseek_v4_profile('deepseek-v4-flash', %w[
                              deepseek-v4-flash
                              deepseek-chat
                              deepseek-reasoner
                            ])
      ].freeze

      # 根据模型名称解析匹配的配置文件
      # @param model [String, nil] 模型名称
      # @param profiles [Array<Hash>] 要搜索的配置文件列表
      # @return [Hash, nil] 匹配的配置文件
      def resolve(model, profiles = MODEL_CONTEXT_PROFILES)
        normalized = normalize_model_id(model)
        return nil if normalized.empty?

        profiles.find do |profile|
          profile[:model_ids].any? do |model_id|
            normalized == model_id || normalized.end_with?("/#{model_id}")
          end
        end
      end

      # 获取模型的上下文阈值
      # @param model [String, nil] 模型名称
      # @param fallback [Hash] 回退阈值
      # @param profiles [Array<Hash>] 要搜索的配置文件列表
      # @return [Hash] 阈值配置
      def context_thresholds(model, fallback = DEFAULT_CONTEXT_THRESHOLDS, profiles = MODEL_CONTEXT_PROFILES)
        profile = resolve(model, profiles)
        return fallback unless profile

        {
          soft_threshold: profile[:soft_threshold],
          hard_threshold: profile[:hard_threshold]
        }
      end

      # 获取模型的能力信息
      # @param model [String, nil] 模型名称
      # @param profiles [Array<Hash>] 要搜索的配置文件列表
      # @return [Hash] 模型能力信息
      def model_capabilities(model, profiles = MODEL_CONTEXT_PROFILES)
        profile = resolve(model, profiles)
        {
          id: model&.strip || profile&.dig(:canonical_model) || 'auto',
          input_modalities: (profile&.dig(:input_modalities) || DEFAULT_MODEL_INPUT_MODALITIES).dup,
          output_modalities: (profile&.dig(:output_modalities) || DEFAULT_MODEL_OUTPUT_MODALITIES).dup,
          supports_tool_calling: profile&.dig(:supports_tool_calling) != false,
          context_window_tokens: profile&.dig(:context_window_tokens),
          message_parts: (profile&.dig(:message_parts) || DEFAULT_MODEL_MESSAGE_PARTS).dup
        }
      end

      # 验证单个模型上下文配置文件
      # @param profile [Hash] 要验证的配置文件
      # @param context [String] 错误消息的上下文
      # @raise [ArgumentError] 验证失败时抛出
      def validate_model_context_profile_config(profile, context = 'model context profile')
        return unless profile.is_a?(Hash)

        validate_aliases(profile[:aliases], context) if profile.key?(:aliases)
        if profile.key?(:context_window_tokens)
          validate_context_window_tokens(profile[:context_window_tokens],
                                         context)
        end
        validate_ratio(profile[:soft_ratio], 'softRatio', context) if profile.key?(:soft_ratio)
        validate_ratio(profile[:hard_ratio], 'hardRatio', context) if profile.key?(:hard_ratio)
        validate_positive_integer(profile[:soft_threshold], 'softThreshold', context) if profile.key?(:soft_threshold)
        validate_positive_integer(profile[:hard_threshold], 'hardThreshold', context) if profile.key?(:hard_threshold)
        validate_modalities(profile[:input_modalities], 'inputModalities', context) if profile.key?(:input_modalities)
        if profile.key?(:output_modalities)
          validate_modalities(profile[:output_modalities], 'outputModalities',
                              context)
        end
        if profile.key?(:supports_tool_calling)
          validate_boolean(profile[:supports_tool_calling], 'supportsToolCalling',
                           context)
        end
        validate_message_parts(profile[:message_parts], context) if profile.key?(:message_parts)

        return unless profile.key?(:context_compaction)

        validate_context_compaction(profile[:context_compaction], context)
      end

      # 验证模型配置哈希（包含 profiles 的顶层配置）
      # @param config [Hash] 要验证的配置
      # @raise [ArgumentError] 验证失败时抛出
      def validate_model_config(config)
        return unless config.is_a?(Hash)

        profiles = config[:profiles]
        return unless profiles

        raise ArgumentError, 'model config "profiles" must be a Hash' unless profiles.is_a?(Hash)

        profiles.each do |model_id, raw_profile|
          validate_model_context_profile_config(raw_profile, "model profile \"#{model_id}\"")
        end
      end

      # 从配置创建模型配置文件列表
      # @param config [Hash, nil] 配置
      # @return [Array<Hash>] 配置文件列表
      def from_config(config = nil)
        validate_model_config(config) if config.is_a?(Hash)

        by_canonical = {}
        MODEL_CONTEXT_PROFILES.each do |profile|
          by_canonical[normalize_model_id(profile[:canonical_model])] = profile
        end

        profile_groups = profile_groups_from_config(config)
        return by_canonical.values if profile_groups.empty?

        profile_groups.each do |profiles|
          profiles.each do |model_id, raw_profile|
            canonical = normalize_model_id(model_id)
            next if canonical.empty?

            validate_model_context_profile_config(raw_profile, "model profile \"#{model_id}\"")

            current = by_canonical[canonical]
            by_canonical[canonical] = merge_profile(canonical, current, raw_profile)
          end
        end

        by_canonical.values
      end

      # 创建 DeepSeek V4 模型配置文件（实例方法版本）
      # @param canonical_model [String] 规范模型名称
      # @param model_ids [Array<String>] 模型 ID 列表
      # @return [Hash] 配置文件
      def deepseek_v4_profile(canonical_model, model_ids)
        {
          canonical_model: canonical_model,
          model_ids: model_ids,
          context_window_tokens: DEEPSEEK_V4_CONTEXT_WINDOW_TOKENS,
          soft_threshold: (DEEPSEEK_V4_CONTEXT_WINDOW_TOKENS * DEEPSEEK_V4_SOFT_THRESHOLD_RATIO).floor,
          hard_threshold: (DEEPSEEK_V4_CONTEXT_WINDOW_TOKENS * DEEPSEEK_V4_HARD_THRESHOLD_RATIO).floor,
          input_modalities: DEFAULT_MODEL_INPUT_MODALITIES.dup,
          output_modalities: DEFAULT_MODEL_OUTPUT_MODALITIES.dup,
          supports_tool_calling: true,
          message_parts: DEFAULT_MODEL_MESSAGE_PARTS.dup
        }
      end

      # 合并模型配置文件
      # @param canonical_model [String] 规范模型名称
      # @param current [Hash, nil] 当前配置文件
      # @param input [Hash] 输入配置
      # @return [Hash] 合并后的配置文件
      def merge_profile(canonical_model, current, input)
        compaction = input[:context_compaction] || {}
        configured_context_window = input[:context_window_tokens] || current&.dig(:context_window_tokens)

        soft_threshold = compaction[:soft_threshold] || input[:soft_threshold] || threshold_from_window(
          context_window_tokens: configured_context_window,
          ratio: compaction[:soft_ratio] || input[:soft_ratio],
          fallback_ratio: current ? current[:soft_threshold].to_f / current[:context_window_tokens] : DEEPSEEK_V4_SOFT_THRESHOLD_RATIO,
          fallback_threshold: current&.dig(:soft_threshold)
        )

        hard_threshold = compaction[:hard_threshold] || input[:hard_threshold] || threshold_from_window(
          context_window_tokens: configured_context_window,
          ratio: compaction[:hard_ratio] || input[:hard_ratio],
          fallback_ratio: current ? current[:hard_threshold].to_f / current[:context_window_tokens] : DEEPSEEK_V4_HARD_THRESHOLD_RATIO,
          fallback_threshold: current&.dig(:hard_threshold)
        )

        context_window_tokens = configured_context_window || [soft_threshold || 0, hard_threshold || 0].max

        unless context_window_tokens && soft_threshold && hard_threshold
          raise "model context profile \"#{canonical_model}\" needs a context window or thresholds"
        end

        if hard_threshold < soft_threshold
          raise "model context profile \"#{canonical_model}\" hard threshold must be >= soft threshold"
        end

        model_ids = unique_model_ids([
                                       canonical_model,
                                       *(current&.dig(:model_ids) || []),
                                       *(input[:aliases] || [])
                                     ])

        {
          canonical_model: canonical_model,
          model_ids: model_ids,
          context_window_tokens: context_window_tokens,
          soft_threshold: soft_threshold,
          hard_threshold: hard_threshold,
          input_modalities: unique_values(input[:input_modalities] || current&.dig(:input_modalities) || DEFAULT_MODEL_INPUT_MODALITIES),
          output_modalities: unique_values(input[:output_modalities] || current&.dig(:output_modalities) || DEFAULT_MODEL_OUTPUT_MODALITIES),
          supports_tool_calling: input[:supports_tool_calling].nil? ? (current&.dig(:supports_tool_calling) != false) : input[:supports_tool_calling],
          message_parts: unique_values(input[:message_parts] || current&.dig(:message_parts) || DEFAULT_MODEL_MESSAGE_PARTS)
        }
      end

      # 根据上下文窗口计算阈值
      # @param options [Hash] 选项
      # @return [Integer, nil] 阈值
      def threshold_from_window(options)
        return options[:fallback_threshold] unless options[:context_window_tokens]

        (options[:context_window_tokens] * (options[:ratio] || options[:fallback_ratio])).floor
      end

      # 从配置中提取配置文件组
      # @param config [Hash, nil] 配置
      # @return [Array<Hash>] 配置文件组列表
      def profile_groups_from_config(config)
        return [] unless config

        groups = []
        groups << config[:context_compaction][:model_profiles] if config[:context_compaction]&.dig(:model_profiles)
        groups << config[:models][:profiles] if config[:models]&.dig(:profiles)
        groups << config[:profiles] if config[:profiles]
        groups << config[:model_profiles] if config[:model_profiles]
        groups
      end

      # 获取唯一的模型 ID 列表
      # @param values [Array<String>] 值列表
      # @return [Array<String] 唯一的模型 ID
      def unique_model_ids(values)
        out = []
        seen = Set.new
        values.each do |value|
          normalized = normalize_model_id(value)
          next if normalized.empty? || seen.include?(normalized)

          seen.add(normalized)
          out << normalized
        end
        out
      end

      # 获取唯一的值列表
      # @param values [Array] 值列表
      # @return [Array] 唯一的值
      def unique_values(values)
        values.uniq
      end

      # 验证别名配置
      # @param value [Object] 要检查的值
      # @return [Boolean]
      def validate_aliases(value, context)
        return if value.is_a?(Array) && value.all?(String)

        raise ArgumentError, "#{context} \"aliases\" must be an Array of strings"
      end

      # 验证上下文窗口 token 数
      # @param value [Object] 要检查的值
      # @param context [String] 错误上下文
      def validate_context_window_tokens(value, context)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{context} \"contextWindowTokens\" must be a positive integer"
      end

      # 验证比例值
      # @param value [Object] 要检查的值
      # @param field [String] 字段名
      # @param context [String] 错误上下文
      def validate_ratio(value, field, context)
        return if value.is_a?(Numeric) && value >= 0 && value <= 1

        raise ArgumentError, "#{context} \"#{field}\" must be a number between 0 and 1"
      end

      # 验证正整数
      # @param value [Object] 要检查的值
      # @param field [String] 字段名
      # @param context [String] 错误上下文
      def validate_positive_integer(value, field, context)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{context} \"#{field}\" must be a positive integer"
      end

      # 验证模态配置
      # @param value [Object] 要检查的值
      # @param field [String] 字段名
      # @param context [String] 错误上下文
      def validate_modalities(value, field, context)
        valid = field == 'inputModalities' ? VALID_INPUT_MODALITIES : VALID_OUTPUT_MODALITIES
        return if value.is_a?(Array) && value.all? { |v| valid.include?(v) }

        raise ArgumentError, "#{context} \"#{field}\" must be an Array of #{valid.join(', ')}"
      end

      # 验证布尔值
      # @param value [Object] 要检查的值
      # @param field [String] 字段名
      # @param context [String] 错误上下文
      def validate_boolean(value, field, context)
        return if [true, false].include?(value)

        raise ArgumentError, "#{context} \"#{field}\" must be a boolean"
      end

      # 验证消息部分类型
      # @param value [Object] 要检查的值
      # @param context [String] 错误上下文
      def validate_message_parts(value, context)
        return if value.is_a?(Array) && value.all? { |v| VALID_MESSAGE_PARTS.include?(v) }

        raise ArgumentError, "#{context} \"messageParts\" must be an Array of #{VALID_MESSAGE_PARTS.join(', ')}"
      end

      # 验证上下文压缩配置
      # @param compaction [Object] 压缩配置
      # @param context [String] 错误上下文
      def validate_context_compaction(compaction, context)
        raise ArgumentError, "#{context} \"contextCompaction\" must be a Hash" unless compaction.is_a?(Hash)

        c = "#{context} contextCompaction"
        validate_ratio(compaction[:soft_ratio], 'softRatio', c) if compaction.key?(:soft_ratio)
        validate_ratio(compaction[:hard_ratio], 'hardRatio', c) if compaction.key?(:hard_ratio)
        validate_positive_integer(compaction[:soft_threshold], 'softThreshold', c) if compaction.key?(:soft_threshold)
        validate_positive_integer(compaction[:hard_threshold], 'hardThreshold', c) if compaction.key?(:hard_threshold)
      end

      # 标准化模型 ID
      # @param model [String, nil] 模型名称
      # @return [String] 标准化后的模型 ID
      def normalize_model_id(model)
        normalized = model&.strip&.downcase || ''
        normalized == 'auto' ? '' : normalized
      end
    end
  end
end
