# frozen_string_literal: true

# 文件用途：DeepForge 配置加载器和验证器
# 使用方法：从 JSON 配置文件读取并验证 DeepForge 运行时配置。支持服务端配置、模型配置、
#           上下文压缩配置、运行时调优配置等模块的验证和加载。

require 'json'
require 'fileutils'

module DeepForge
  module Config
    # 配置文件名
    DEEPFORGE_CONFIG_FILENAME = 'config.json'
    # 默认模型
    DEFAULT_DEEPFORGE_MODEL = 'deepseek-v4-pro'
    # 默认审批策略
    DEFAULT_APPROVAL_POLICY = 'suggest'
    # 默认沙箱模式
    DEFAULT_SANDBOX_MODE = 'off'

    # DeepForge 配置加载器和验证器。
    class DeepForgeConfig
      attr_reader :path, :config

      # 初始化配置加载器
      # 参数：path - 配置文件路径
      def initialize(path)
        @path = path
        @config = {}
      end

      # 从指定路径读取并验证配置文件
      # 参数：path - 配置文件路径（支持 ~ 展开）
      # 返回值：DeepForgeConfig 实例
      # 异常：文件不存在或 JSON 解析失败时抛出异常
      def self.read_config_file(path)
        resolved_path = expand_home_path(path)
        text = File.read(resolved_path)

        begin
          json = JSON.parse(text)
        rescue JSON::ParserError => e
          raise "Failed to parse DeepForge config JSON at #{resolved_path}: #{e.message}"
        end

        config = validate_config(json)
        new(resolved_path).tap { |c| c.instance_variable_set(:@config, config) }
      end

      # 可选地读取配置文件，文件不存在时返回 nil
      # 参数：path - 配置文件路径（可选）
      # 返回值：DeepForgeConfig 实例或 nil
      def self.read_optional_config_file(path)
        return nil unless path

        resolved_path = expand_home_path(path)
        return nil unless File.exist?(resolved_path)

        read_config_file(resolved_path)
      end

      # 根据数据目录路径生成配置文件路径
      # 参数：data_dir - 数据目录路径（可选）
      # 返回值：String 或 nil，配置文件的完整路径
      def self.config_path_for_data_dir(data_dir)
        trimmed = data_dir&.strip
        return nil if trimmed.nil? || trimmed.empty?

        File.join(expand_home_path(trimmed), DEEPFORGE_CONFIG_FILENAME)
      end

      # 展开路径中的 ~ 为用户主目录
      # 参数：path - 可能包含 ~ 的路径
      # 返回值：String，展开后的完整路径
      def self.expand_home_path(path)
        if path.start_with?('~')
          path.sub(%r{^~(?=$|/)}, Dir.home)
        else
          path
        end
      end

      # 验证并转换 JSON 配置为内部格式
      # 参数：json - 从 JSON 文件解析出的原始哈希
      # 返回值：Hash，验证后的配置哈希
      def self.validate_config(json)
        config = {}

        config[:serve] = validate_serve_config(json['serve']) if json['serve'].is_a?(Hash)

        config[:models] = validate_model_config(json['models']) if json['models'].is_a?(Hash)

        if json['contextCompaction'].is_a?(Hash)
          config[:context_compaction] = validate_context_compaction_config(json['contextCompaction'])
        end

        config[:runtime] = validate_runtime_tuning_config(json['runtime']) if json['runtime'].is_a?(Hash)

        config[:capabilities] = json['capabilities'] || {}

        config
      end

      # 验证请求历史清理配置
      # 参数：hygiene - 原始清理配置哈希
      # 返回值：Hash，验证后的配置
      def self.validate_request_history_hygiene_config(hygiene)
        config = {}
        if hygiene['maxToolResultLines'].is_a?(Numeric) && hygiene['maxToolResultLines'].positive?
          config[:max_tool_result_lines] =
            hygiene['maxToolResultLines'].to_i
        end
        if hygiene['maxToolResultBytes'].is_a?(Numeric) && hygiene['maxToolResultBytes'].positive?
          config[:max_tool_result_bytes] =
            hygiene['maxToolResultBytes'].to_i
        end
        if hygiene['maxToolResultTokens'].is_a?(Numeric) && hygiene['maxToolResultTokens'].positive?
          config[:max_tool_result_tokens] =
            hygiene['maxToolResultTokens'].to_i
        end
        if hygiene['maxToolArgumentStringBytes'].is_a?(Numeric) && hygiene['maxToolArgumentStringBytes'].positive?
          config[:max_tool_argument_string_bytes] =
            hygiene['maxToolArgumentStringBytes'].to_i
        end
        if hygiene['maxToolArgumentStringTokens'].is_a?(Numeric) && hygiene['maxToolArgumentStringTokens'].positive?
          config[:max_tool_argument_string_tokens] =
            hygiene['maxToolArgumentStringTokens'].to_i
        end
        if hygiene['maxArrayItems'].is_a?(Numeric) && hygiene['maxArrayItems'].positive?
          config[:max_array_items] =
            hygiene['maxArrayItems'].to_i
        end
        config
      end

      # 验证 token 经济模式配置
      # 参数：te - 原始 token 经济配置哈希
      # 返回值：Hash，验证后的配置
      def self.validate_token_economy_config(te)
        config = {}
        config[:enabled] = te['enabled'] if te.key?('enabled')
        config[:compress_tool_descriptions] = te['compressToolDescriptions'] if te.key?('compressToolDescriptions')
        config[:compress_tool_results] = te['compressToolResults'] if te.key?('compressToolResults')
        config[:concise_responses] = te['conciseResponses'] if te.key?('conciseResponses')
        if te['historyHygiene'].is_a?(Hash)
          config[:history_hygiene] = validate_request_history_hygiene_config(te['historyHygiene'])
        end
        config
      end

      # 验证服务端配置
      # 参数：serve - 原始服务端配置哈希
      # 返回值：Hash，验证后的配置（含 host, port, data_dir, model 等）
      def self.validate_serve_config(serve)
        config = {}
        config[:host] = serve['host'] if serve['host'].is_a?(String)
        config[:port] = serve['port'].to_i if serve['port'].is_a?(Numeric)
        config[:data_dir] = serve['dataDir'] if serve['dataDir'].is_a?(String)
        config[:runtime_token] = serve['runtimeToken'] if serve['runtimeToken'].is_a?(String)
        config[:api_key] = serve['apiKey'] if serve['apiKey'].is_a?(String)
        config[:base_url] = serve['baseUrl'] if serve['baseUrl'].is_a?(String)
        config[:model] = serve['model'] if serve['model'].is_a?(String)
        config[:approval_policy] = serve['approvalPolicy'] || DEFAULT_APPROVAL_POLICY
        config[:sandbox_mode] = serve['sandboxMode'] || DEFAULT_SANDBOX_MODE
        config[:token_economy_mode] = serve['tokenEconomyMode'] if serve.key?('tokenEconomyMode')
        if serve['tokenEconomy'].is_a?(Hash)
          config[:token_economy] =
            validate_token_economy_config(serve['tokenEconomy'])
        end
        config[:insecure] = serve['insecure'] if serve.key?('insecure')

        if serve['storage'].is_a?(Hash)
          config[:storage] = {
            backend: serve['storage']['backend'] || 'hybrid',
            sqlite_path: serve['storage']['sqlitePath']
          }
        end

        config
      end

      # 验证模型配置
      # 参数：models - 原始模型配置哈希
      # 返回值：Hash，验证后的配置（含 profiles 等）
      def self.validate_model_config(models)
        config = {}
        if models['profiles'].is_a?(Hash)
          config[:profiles] = models['profiles'].transform_values do |profile|
            validate_model_profile_config(profile)
          end
        end
        config
      end

      # 验证模型配置档案
      # 参数：profile - 原始模型档案配置哈希
      # 返回值：Hash，验证后的配置（含 aliases, context_window_tokens 等）
      def self.validate_model_profile_config(profile)
        config = {}
        config[:aliases] = profile['aliases'] if profile['aliases'].is_a?(Array)
        if profile['contextWindowTokens'].is_a?(Numeric)
          config[:context_window_tokens] =
            profile['contextWindowTokens'].to_i
        end
        config[:supports_tool_calling] = profile['supportsToolCalling'] if profile.key?('supportsToolCalling')

        if profile['contextCompaction'].is_a?(Hash)
          config[:context_compaction] = validate_context_compaction_profile(profile['contextCompaction'])
        end

        config
      end

      # 验证上下文压缩的模型档案配置
      # 参数：profile - 原始压缩档案配置哈希
      # 返回值：Hash，验证后的配置（含 soft_ratio, hard_ratio 等）
      def self.validate_context_compaction_profile(profile)
        config = {}
        config[:soft_ratio] = profile['softRatio'].to_f if profile['softRatio'].is_a?(Numeric)
        config[:hard_ratio] = profile['hardRatio'].to_f if profile['hardRatio'].is_a?(Numeric)
        config[:soft_threshold] = profile['softThreshold'].to_i if profile['softThreshold'].is_a?(Numeric)
        config[:hard_threshold] = profile['hardThreshold'].to_i if profile['hardThreshold'].is_a?(Numeric)
        config
      end

      # 验证上下文压缩配置
      # 参数：compaction - 原始压缩配置哈希
      # 返回值：Hash，验证后的配置（含 default_soft_threshold, summary_mode 等）
      def self.validate_context_compaction_config(compaction)
        config = {}
        if compaction['defaultSoftThreshold'].is_a?(Numeric)
          config[:default_soft_threshold] =
            compaction['defaultSoftThreshold'].to_i
        end
        if compaction['defaultHardThreshold'].is_a?(Numeric)
          config[:default_hard_threshold] =
            compaction['defaultHardThreshold'].to_i
        end
        config[:summary_mode] = compaction['summaryMode'] if %w[heuristic model].include?(compaction['summaryMode'])
        if compaction['summaryTimeoutMs'].is_a?(Numeric)
          config[:summary_timeout_ms] =
            compaction['summaryTimeoutMs'].to_i
        end
        if compaction['summaryMaxTokens'].is_a?(Numeric)
          config[:summary_max_tokens] =
            compaction['summaryMaxTokens'].to_i
        end

        if compaction['modelProfiles'].is_a?(Hash)
          config[:model_profiles] = compaction['modelProfiles'].transform_values do |profile|
            validate_model_profile_config(profile)
          end
        end

        config
      end

      # 验证运行时调优配置
      # 参数：runtime - 原始运行时配置哈希
      # 返回值：Hash，验证后的配置（含 tool_storm, tool_argument_repair 等）
      def self.validate_runtime_tuning_config(runtime)
        config = {}

        if runtime['toolStorm'].is_a?(Hash)
          tool_storm = {}
          tool_storm[:enabled] = runtime['toolStorm']['enabled'] if runtime['toolStorm'].key?('enabled')
          if runtime['toolStorm']['windowSize'].is_a?(Numeric)
            tool_storm[:window_size] =
              runtime['toolStorm']['windowSize'].to_i
          end
          if runtime['toolStorm']['threshold'].is_a?(Numeric)
            tool_storm[:threshold] =
              runtime['toolStorm']['threshold'].to_i
          end
          config[:tool_storm] = tool_storm
        end

        if runtime['toolArgumentRepair'].is_a?(Hash)
          tool_argument_repair = {}
          if runtime['toolArgumentRepair']['maxStringBytes'].is_a?(Numeric)
            tool_argument_repair[:max_string_bytes] =
              runtime['toolArgumentRepair']['maxStringBytes'].to_i
          end
          config[:tool_argument_repair] = tool_argument_repair
        end

        config
      end
    end
  end
end
