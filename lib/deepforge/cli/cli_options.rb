# frozen_string_literal: true

#
# 文件用途：CLI 选项解析与配置管理模块
# 功能说明：定义 serve 命令的默认配置、ServeOptions 结构体、命令行参数解析逻辑，以及配置文件加载
# 使用方法：调用 DeepForge::CLI.parse_serve_options(argv, env) 解析命令行参数并返回 ServeOptions 对象

require 'optparse'

module DeepForge
  module CLI
    # 服务默认监听端口
    DEFAULT_SERVE_PORT = 8899

    # 默认使用的模型名称
    DEFAULT_SERVE_MODEL = 'deepseek-chat'

    # 默认审批策略：on-request 表示按需审批
    DEFAULT_APPROVAL_POLICY = 'on-request'

    # 默认沙箱模式：workspace-write 允许写入工作区
    DEFAULT_SANDBOX_MODE = 'workspace-write'

    # 默认存储配置：使用混合存储后端
    DEFAULT_STORAGE_CONFIG = {
      backend: 'hybrid'
    }.freeze

    # 默认能力配置：MCP 服务器、Web、技能、附件、记忆、子代理等模块的开关
    DEFAULT_DEEPFORGE_CAPABILITIES_CONFIG = {
      mcp: { servers: {} },
      web: {},
      skills: { roots: [] },
      attachments: { enabled: false },
      memory: { enabled: false },
      subagents: { enabled: false }
    }.freeze

    # ServeOptions 结构体：存储经过验证的所有 serve 命令选项
    ServeOptions = Struct.new(
      :configPath, :host, :port, :dataDir, :runtimeToken,
      :apiKey, :baseUrl, :model, :approvalPolicy, :sandboxMode,
      :tokenEconomyMode, :tokenEconomy, :insecure, :storage,
      :models, :contextCompaction, :runtime, :capabilities,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        kwargs[:host] ||= '127.0.0.1'
        kwargs[:port] ||= DEFAULT_SERVE_PORT
        kwargs[:dataDir] ||= ''
        kwargs[:runtimeToken] ||= ''
        kwargs[:apiKey] ||= ''
        kwargs[:baseUrl] ||= 'https://api.deepseek.com/beta'
        kwargs[:model] ||= DEFAULT_SERVE_MODEL
        kwargs[:approvalPolicy] ||= DEFAULT_APPROVAL_POLICY
        kwargs[:sandboxMode] ||= DEFAULT_SANDBOX_MODE
        kwargs[:tokenEconomyMode] ||= false
        kwargs[:insecure] ||= false
        kwargs[:storage] ||= DEFAULT_STORAGE_CONFIG
        kwargs[:capabilities] ||= DEFAULT_DEEPFORGE_CAPABILITIES_CONFIG
        super
      end
    end

    # 默认的 serve 配置对象实例
    DEFAULT_SERVE_OPTIONS = ServeOptions.new

    # 方法功能：解析 `deepforge serve` 命令行参数，合并环境变量和配置文件
    # 参数：argv - 命令行参数数组；env - 环境变量哈希
    # 返回值：ServeOptions 结构体实例
    # 优先级：命令行参数 > 环境变量 > 配置文件 > 默认值
    def self.parse_serve_options(argv, env = {})
      raw = {}
      i = 0
      while i < argv.length
        token = argv[i]
        unless token.start_with?('--')
          i += 1
          next
        end

        eq_index = token.index('=')
        key = eq_index ? token[2...eq_index] : token[2..]
        value = 'true'

        if eq_index
          value = token[(eq_index + 1)..]
        elsif i + 1 < argv.length && !argv[i + 1].start_with?('--')
          value = argv[i + 1]
          i += 1
        end

        raw[key] = value
        i += 1
      end

      # Load config file
      loaded_config = load_serve_config(raw, env)
      config_serve = loaded_config&.dig(:config, :serve) || {}

      # Parse token economy mode
      token_economy_mode = boolean_flag(raw, 'token-economy') ||
                           boolean_flag(raw, 'token-economy-mode') ||
                           boolean_flag(raw, 'tokenEconomyMode') ||
                           env_boolean(env['DEEPFORGE_TOKEN_ECONOMY_MODE']) ||
                           config_serve.dig(:tokenEconomy, :enabled) ||
                           config_serve[:tokenEconomyMode] ||
                           false

      # Build options
      ServeOptions.new(
        config_path: loaded_config&.dig(:path),
        host: raw['host'] || env['DEEPFORGE_HOST'] || config_serve[:host] || '127.0.0.1',
        port: (raw['port'] || env['DEEPFORGE_PORT'] || config_serve[:port] || DEFAULT_SERVE_PORT).to_i,
        data_dir: raw['data-dir'] || raw['dataDir'] || env['DEEPFORGE_DATA_DIR'] || config_serve[:dataDir] || '',
        runtime_token: raw['runtime-token'] || raw['runtimeToken'] || env['DEEPFORGE_RUNTIME_TOKEN'] || config_serve[:runtime_token] || '',
        api_key: raw['api-key'] || raw['apiKey'] || env['DEEPSEEK_API_KEY'] || config_serve[:apiKey] || '',
        base_url: raw['base-url'] || raw['baseUrl'] || env['DEEPFORGE_BASE_URL'] || env['DEEPSEEK_BASE_URL'] || config_serve[:baseUrl] || 'https://api.deepseek.com/beta',
        model: raw['model'] || env['DEEPFORGE_MODEL'] || config_serve[:model] || DEFAULT_SERVE_MODEL,
        approval_policy: raw['approval-policy'] || config_serve[:approvalPolicy] || DEFAULT_APPROVAL_POLICY,
        sandbox_mode: raw['sandbox-mode'] || config_serve[:sandboxMode] || DEFAULT_SANDBOX_MODE,
        token_economy_mode: token_economy_mode,
        token_economy: (config_serve[:tokenEconomy] || {}).merge(enabled: token_economy_mode),
        insecure: parse_insecure(raw, config_serve),
        storage: {
          backend: storage_backend_from_raw_or_env(raw, env) || config_serve.dig(:storage, :backend) || 'hybrid',
          sqlitePath: storage_sqlite_path_from_raw_or_env(raw, env) || config_serve.dig(:storage, :sqlitePath)
        }.compact,
        models: loaded_config&.dig(:config, :models),
        context_compaction: loaded_config&.dig(:config, :contextCompaction),
        runtime: loaded_config&.dig(:config, :runtime),
        capabilities: loaded_config&.dig(:config, :capabilities) || DEFAULT_DEEPFORGE_CAPABILITIES_CONFIG
      )
    end

    # 方法功能：验证并构造 ServeOptions 对象
    # 参数：input - 选项哈希
    # 返回值：ServeOptions 实例
    def self.validate_serve_options(input)
      ServeOptions.new(**input)
    end

    # serve 命令的帮助文档文本
    SERVE_USAGE = <<~USAGE.freeze
      deepforge serve [options]

      Options:
        --config <path>          JSON config file (default: {data-dir}/config.json when present)
        --host <host>            Bind address (default 127.0.0.1)
        --port <port>            HTTP port (default #{DEFAULT_SERVE_PORT})
        --data-dir <path>        Root directory for threads, events, and usage
        --runtime-token <token>  Bearer token for /v1/* requests
        --api-key <key>          DeepSeek-compatible API key
        --base-url <url>         DeepSeek-compatible base URL
        --model <model>          Default model id
        --approval-policy <p>    on-request | untrusted | never | auto | suggest
        --sandbox-mode <mode>    read-only | workspace-write | danger-full-access | external-sandbox
        --token-economy          Compress safe tool context before model calls
        --insecure               Disable bearer token check (local dev only)
        --storage-backend <b>    hybrid | file (default hybrid)
        --sqlite-path <path>     SQLite index path for hybrid storage
    USAGE

    # 退出码常量定义
    module ServeExitCode
      OK = 0
      USAGE = 64
      CONFIG = 78
      RUNTIME = 70
    end

    # 方法功能：安全解析 serve 选项，包含异常捕获和必要参数校验
    # 参数：argv - 命令行参数；env - 环境变量
    # 返回值：Hash，成功时含 :ok 和 :options，失败时含 :exitCode 和 :message
    def self.parse_serve_options_safe(argv, env = {})
      options = parse_serve_options(argv, env)

      if options.data_dir.nil? || options.data_dir.empty?
        return {
          ok: false,
          exitCode: ServeExitCode::CONFIG,
          message: 'serve requires --data-dir <path>'
        }
      end

      { ok: true, options: options }
    rescue StandardError => e
      {
        ok: false,
        exitCode: ServeExitCode::CONFIG,
        message: e.message
      }
    end

    # 方法功能：从配置文件加载 serve 配置，支持显式指定路径和 data-dir 下自动查找
    # 参数：raw - 原始解析选项；env - 环境变量
    # 返回值：配置哈希或 nil
    def self.load_serve_config(raw, env)
      explicit_config_path = string_flag(raw, 'config') ||
                             string_flag(raw, 'config-file') ||
                             env['DEEPFORGE_CONFIG']

      return read_deepforge_config_file(explicit_config_path) if explicit_config_path

      data_dir = data_dir_from_raw_or_env(raw, env)
      return nil unless data_dir

      config_path = File.join(data_dir, 'config.json')
      read_optional_deepforge_config_file(config_path)
    end

    # 方法功能：读取并解析指定路径的 JSON 配置文件
    # 参数：path - 配置文件路径
    # 返回值：解析后的配置哈希或 nil（文件不存在或解析失败时）
    def self.read_deepforge_config_file(path)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path), symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    # 方法功能：读取可选的配置文件（不存在时返回 nil）
    # 参数：path - 配置文件路径
    # 返回值：配置哈希或 nil
    def self.read_optional_deepforge_config_file(path)
      read_deepforge_config_file(path)
    end

    # 方法功能：从原始选项或环境变量中获取数据目录路径
    # 参数：raw - 原始选项哈希；env - 环境变量
    # 返回值：数据目录路径字符串或 nil
    def self.data_dir_from_raw_or_env(raw, env)
      string_flag(raw, 'data-dir') ||
        string_flag(raw, 'dataDir') ||
        env['DEEPFORGE_DATA_DIR']
    end

    # 方法功能：从原始选项或环境变量中获取存储后端类型（hybrid 或 file）
    # 参数：raw - 原始选项哈希；env - 环境变量
    # 返回值：存储后端字符串或 nil
    def self.storage_backend_from_raw_or_env(raw, env)
      value = string_flag(raw, 'storage-backend') ||
              string_flag(raw, 'storageBackend') ||
              env['DEEPFORGE_STORAGE_BACKEND']

      return nil unless value
      return value if %w[hybrid file].include?(value)

      value
    end

    # 方法功能：从原始选项或环境变量中获取 SQLite 数据库文件路径
    # 参数：raw - 原始选项哈希；env - 环境变量
    # 返回值：SQLite 路径字符串或 nil
    def self.storage_sqlite_path_from_raw_or_env(raw, env)
      string_flag(raw, 'sqlite-path') ||
        string_flag(raw, 'sqlitePath') ||
        env['DEEPFORGE_SQLITE_PATH']
    end

    # 方法功能：从原始选项哈希中获取字符串类型的标志值
    # 参数：raw - 原始选项哈希；key - 标志键名
    # 返回值：字符串值或 nil（值为 'true' 时视为布尔标志返回 nil）
    def self.string_flag(raw, key)
      value = raw[key]
      value.is_a?(String) && value != 'true' ? value : nil
    end

    # 方法功能：从原始选项哈希中获取布尔类型的标志值
    # 参数：raw - 原始选项哈希；key - 标志键名
    # 返回值：布尔值或 nil
    def self.boolean_flag(raw, key)
      value = raw[key]
      return nil if value.nil?
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

      env_boolean(value)
    end

    # 方法功能：将字符串解析为布尔值（支持 '0'、'false'、'off'、'no' 为 false）
    # 参数：value - 字符串值
    # 返回值：布尔值或 nil
    def self.env_boolean(value)
      return nil if value.nil?

      normalized = value.strip.downcase
      return false if normalized.empty?
      return false if %w[0 false off no].include?(normalized)

      true
    end

    # 方法功能：解析 insecure 标志，用于禁用 Bearer Token 认证（仅限本地开发）
    # 参数：raw - 原始选项哈希；config_serve - 配置文件中的 serve 选项
    # 返回值：布尔值
    def self.parse_insecure(raw, config_serve)
      value = raw['insecure']
      if value.is_a?(String)
        value != 'false' && value != '0'
      elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
        value
      else
        config_serve[:insecure] || false
      end
    end
  end
end
