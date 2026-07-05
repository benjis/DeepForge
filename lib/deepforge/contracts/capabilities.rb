# frozen_string_literal: true

# 文件用途：定义运行时能力配置和能力清单的数据结构
# 使用方法：用于声明各子系统（MCP、Web、技能、子代理、附件、内存）的配置和状态

module DeepForge
  module Contracts
    RUNTIME_CAPABILITY_CONTRACT_VERSION = 1

    # 运行时能力状态：表示能力的可用状态
    module RuntimeCapabilityStatus
      AVAILABLE = 'available'
      DISABLED = 'disabled'
      UNAVAILABLE = 'unavailable'
    end

    # 运行时能力状态结构：描述某项能力的启用和可用状态
    RuntimeCapabilityState = Struct.new(
      :status,
      :enabled,
      :available,
      :reason,
      keyword_init: true
    )

    # 模型输入模态常量：定义模型支持的输入类型
    module ModelInputModality
      TEXT = 'text'
      IMAGE = 'image'
    end

    # 模型消息部件支持常量：定义模型支持的消息部件类型
    module ModelMessagePartSupport
      TEXT = 'text'
      IMAGE_URL = 'image_url'
      INPUT_IMAGE = 'input_image'
    end

    # 模型能力元数据：描述模型的输入输出模态、工具调用支持和上下文窗口大小
    ModelCapabilityMetadata = Struct.new(
      :id,
      :input_modalities,
      :output_modalities,
      :supports_tool_calling,
      :context_window_tokens,
      :message_parts,
      keyword_init: true
    )

    # MCP 传输类型常量：定义 MCP 服务器的连接方式（标准输入输出、HTTP、SSE）
    module McpTransportKind
      STDIO = 'stdio'
      STREAMABLE_HTTP = 'streamable-http'
      SSE = 'sse'
    end

    # MCP 信任范围常量：定义 MCP 服务器的信任级别（用户级、工作空间级）
    module McpTrustScope
      USER = 'user'
      WORKSPACE = 'workspace'
    end

    # MCP 工具发现模式常量：定义 MCP 工具的发现方式（直接、搜索、自动）
    module McpToolDiscoveryMode
      DIRECT = 'direct'
      SEARCH = 'search'
      AUTO = 'auto'
    end

    # MCP 搜索配置：控制 MCP 工具搜索的行为参数
    McpSearchConfig = Struct.new(
      :enabled,
      :mode,
      :auto_threshold_tool_count,
      :top_k_default,
      :top_k_max,
      :min_score,
      :bm25,
      keyword_init: true
    )

    # MCP BM25 搜索算法参数配置
    McpSearchBm25Config = Struct.new(
      :k1,
      :b,
      keyword_init: true
    )

    # MCP 服务器配置：定义单个 MCP 服务器的连接参数和信任设置
    McpServerConfig = Struct.new(
      :enabled,
      :transport,
      :command,
      :args,
      :url,
      :headers,
      :env,
      :trust_scope,
      :trusted_workspace_roots,
      :timeout_ms,
      keyword_init: true
    )

    # MCP 能力配置：包含 MCP 总开关、服务器列表和搜索配置
    McpCapabilityConfig = Struct.new(
      :enabled,
      :servers,
      :search,
      keyword_init: true
    )

    # Web 能力配置：控制网页抓取和搜索功能的开关及域名过滤
    WebCapabilityConfig = Struct.new(
      :enabled,
      :fetch_enabled,
      :search_enabled,
      :provider,
      :allow_domains,
      :deny_domains,
      keyword_init: true
    )

    # 技能能力配置：控制技能功能的开关和技能根目录
    SkillsCapabilityConfig = Struct.new(
      :enabled,
      :roots,
      :legacy_skill_md,
      keyword_init: true
    )

    # 子代理能力配置：控制子代理的并行数和最大运行次数
    SubagentsCapabilityConfig = Struct.new(
      :enabled,
      :max_parallel,
      :max_child_runs,
      :default_step_limit, # legacy field, accepted but ignored
      keyword_init: true
    )

    # 从原始配置数据构建子代理配置对象
    # 参数：raw - 原始配置哈希，支持 snake_case 和 camelCase 两种键名
    def self.build_subagents_config(raw)
      SubagentsCapabilityConfig.new(
        enabled: raw['enabled'] || false,
        max_parallel: raw['max_parallel'] || raw['maxParallel'] || 0,
        max_child_runs: raw['max_child_runs'] || raw['maxChildRuns'] || 0,
        default_step_limit: nil # accepted but ignored
      )
    end

    # 附件文本回退默认配置：最大 Base64 数据大小（512KB）
    DEFAULT_ATTACHMENT_TEXT_FALLBACK_MAX_BASE64_BYTES = 512 * 1024
    DEFAULT_ATTACHMENT_TEXT_FALLBACK_MAX_IMAGE_DIMENSION = 1280
    DEFAULT_ATTACHMENT_TEXT_FALLBACK_PREFERRED_MIME_TYPE = 'image/webp'

    # 附件能力配置：定义附件大小限制、MIME类型过滤和文本回退参数
    AttachmentsCapabilityConfig = Struct.new(
      :enabled,
      :max_image_bytes,
      :max_image_dimension,
      :allowed_mime_types,
      :text_fallback_max_base64_bytes,
      :text_fallback_max_image_dimension,
      :text_fallback_preferred_mime_type,
      keyword_init: true
    )

    # 内存能力配置：控制内存功能的开关、作用域和最大注入记录数
    MemoryCapabilityConfig = Struct.new(
      :enabled,
      :scopes,
      :max_injected_records,
      keyword_init: true
    )

    # DeepForge 总能力配置：包含所有子系统的配置
    DeepForgeCapabilitiesConfig = Struct.new(
      :mcp,
      :web,
      :skills,
      :subagents,
      :attachments,
      :memory,
      keyword_init: true
    )

    # 运行时能力清单：对外暴露的完整能力状态报告
    RuntimeCapabilityManifest = Struct.new(
      :contract_version,
      :model,
      :cli,
      :mcp,
      :web,
      :skills,
      :subagents,
      :attachments,
      :memory,
      keyword_init: true
    )

    # 构建默认的能力配置（所有子系统默认禁用）
    def self.build_default_capabilities_config
      DeepForgeCapabilitiesConfig.new(
        mcp: McpCapabilityConfig.new(
          enabled: false,
          servers: {},
          search: build_default_mcp_search_config
        ),
        web: WebCapabilityConfig.new(
          enabled: false,
          fetch_enabled: false,
          search_enabled: false,
          provider: nil,
          allow_domains: [],
          deny_domains: []
        ),
        skills: SkillsCapabilityConfig.new(
          enabled: false,
          roots: [],
          legacy_skill_md: true
        ),
        subagents: SubagentsCapabilityConfig.new(
          enabled: false,
          max_parallel: 0,
          max_child_runs: 0,
          default_step_limit: nil
        ),
        attachments: AttachmentsCapabilityConfig.new(
          enabled: false,
          max_image_bytes: 5 * 1024 * 1024,
          max_image_dimension: 4096,
          allowed_mime_types: ['image/png', 'image/jpeg', 'image/webp'],
          text_fallback_max_base64_bytes: DEFAULT_ATTACHMENT_TEXT_FALLBACK_MAX_BASE64_BYTES,
          text_fallback_max_image_dimension: DEFAULT_ATTACHMENT_TEXT_FALLBACK_MAX_IMAGE_DIMENSION,
          text_fallback_preferred_mime_type: DEFAULT_ATTACHMENT_TEXT_FALLBACK_PREFERRED_MIME_TYPE
        ),
        memory: MemoryCapabilityConfig.new(
          enabled: false,
          scopes: %w[user workspace project],
          max_injected_records: 8
        )
      )
    end

    # 构建默认的 MCP 搜索配置
    def self.build_default_mcp_search_config
      McpSearchConfig.new(
        enabled: false,
        mode: McpToolDiscoveryMode::AUTO,
        auto_threshold_tool_count: 24,
        top_k_default: 5,
        top_k_max: 10,
        min_score: 0.15,
        bm25: McpSearchBm25Config.new(k1: 1.2, b: 0.75)
      )
    end

    # 根据输入构建运行时能力清单
    # 参数：input - 包含配置和运行时状态的哈希
    def self.build_runtime_capability_manifest(input)
      config = input[:config] || DEFAULT_DEEPFORGE_CAPABILITIES_CONFIG
      model = input[:model]

      mcp_input = input[:mcp] || {}
      configured_mcp_servers = mcp_input[:configured_servers] || config.mcp.servers.length
      connected_mcp_servers = mcp_input[:connected_servers] || 0
      mcp_tool_count = mcp_input[:tool_count] || 0
      mcp_state = mcp_capability_state(config.mcp.enabled, connected_mcp_servers, mcp_input[:last_error])

      web_input = input[:web] || {}
      web_fetch_state = provider_capability_state(
        config.web.enabled && config.web.fetch_enabled,
        'web fetch is disabled by config',
        web_input[:fetch_available] == true,
        web_input[:reason] || 'web fetch provider is unavailable'
      )
      web_search_state = provider_capability_state(
        config.web.enabled && config.web.search_enabled,
        'web search is disabled by config',
        web_input[:search_available] == true,
        web_input[:reason] || 'web search provider is unavailable'
      )
      web_state = web_capability_state(config.web.enabled, web_fetch_state, web_search_state, web_input[:reason])

      skills_input = input[:skills] || {}
      configured_skill_roots = skills_input[:configured_roots] || config.skills.roots.length
      discovered_skills = skills_input[:discovered_skills] || 0
      skills_state = skills_capability_state(config.skills.enabled, discovered_skills, skills_input[:reason])

      subagents_input = input[:subagents] || {}
      attachments_input = input[:attachments] || {}
      memory_input = input[:memory] || {}

      RuntimeCapabilityManifest.new(
        contract_version: RUNTIME_CAPABILITY_CONTRACT_VERSION,
        model: model,
        cli: {
          serve: available_state,
          run: unavailable_state('not implemented'),
          chat: unavailable_state('not implemented'),
          exec: unavailable_state('not implemented')
        },
        mcp: {
          status: mcp_state.status,
          enabled: mcp_state.enabled,
          available: mcp_state.available,
          reason: mcp_state.reason,
          configured_servers: configured_mcp_servers,
          connected_servers: connected_mcp_servers,
          tool_count: mcp_tool_count,
          search: {
            enabled: config.mcp.search.enabled,
            mode: config.mcp.search.mode,
            active: mcp_input.dig(:search, :active) || false,
            indexed_tool_count: mcp_input.dig(:search, :indexed_tool_count) || mcp_tool_count,
            advertised_tool_count: mcp_input.dig(:search, :advertised_tool_count) || mcp_tool_count
          }
        },
        web: {
          status: web_state.status,
          enabled: web_state.enabled,
          available: web_state.available,
          reason: web_state.reason,
          fetch: web_fetch_state,
          search: web_search_state,
          provider: web_input[:provider] || config.web.provider
        },
        skills: {
          status: skills_state.status,
          enabled: skills_state.enabled,
          available: skills_state.available,
          reason: skills_state.reason,
          configured_roots: configured_skill_roots,
          discovered_skills: discovered_skills
        },
        subagents: {
          status: provider_capability_state(
            config.subagents.enabled,
            'subagents are disabled by config',
            subagents_input[:available] == true,
            subagents_input[:reason] || 'subagent runtime is unavailable'
          ).then(&:status),
          enabled: config.subagents.enabled,
          available: provider_capability_state(
            config.subagents.enabled,
            'subagents are disabled by config',
            subagents_input[:available] == true,
            subagents_input[:reason] || 'subagent runtime is unavailable'
          ).available,
          reason: provider_capability_state(
            config.subagents.enabled,
            'subagents are disabled by config',
            subagents_input[:available] == true,
            subagents_input[:reason] || 'subagent runtime is unavailable'
          ).reason,
          max_parallel: config.subagents.max_parallel,
          max_child_runs: config.subagents.max_child_runs
        },
        attachments: {
          status: provider_capability_state(
            config.attachments.enabled,
            'attachments are disabled by config',
            attachments_input[:available] == true,
            attachments_input[:reason] || 'attachment store is unavailable'
          ).status,
          enabled: config.attachments.enabled,
          available: provider_capability_state(
            config.attachments.enabled,
            'attachments are disabled by config',
            attachments_input[:available] == true,
            attachments_input[:reason] || 'attachment store is unavailable'
          ).available,
          reason: provider_capability_state(
            config.attachments.enabled,
            'attachments are disabled by config',
            attachments_input[:available] == true,
            attachments_input[:reason] || 'attachment store is unavailable'
          ).reason,
          max_image_bytes: config.attachments.max_image_bytes,
          max_image_dimension: config.attachments.max_image_dimension,
          allowed_mime_types: config.attachments.allowed_mime_types,
          text_fallback_max_base64_bytes: config.attachments.text_fallback_max_base64_bytes,
          text_fallback_max_image_dimension: config.attachments.text_fallback_max_image_dimension,
          text_fallback_preferred_mime_type: config.attachments.text_fallback_preferred_mime_type
        },
        memory: {
          status: provider_capability_state(
            config.memory.enabled,
            'memory is disabled by config',
            memory_input[:available] == true,
            memory_input[:reason] || 'memory store is unavailable'
          ).status,
          enabled: config.memory.enabled,
          available: provider_capability_state(
            config.memory.enabled,
            'memory is disabled by config',
            memory_input[:available] == true,
            memory_input[:reason] || 'memory store is unavailable'
          ).available,
          reason: provider_capability_state(
            config.memory.enabled,
            'memory is disabled by config',
            memory_input[:available] == true,
            memory_input[:reason] || 'memory store is unavailable'
          ).reason,
          scopes: config.memory.scopes,
          max_injected_records: config.memory.max_injected_records
        }
      )
    end

    # 创建"可用"状态的能力状态对象
    def self.available_state
      RuntimeCapabilityState.new(
        status: RuntimeCapabilityStatus::AVAILABLE,
        enabled: true,
        available: true
      )
    end

    # 创建"不可用"状态的能力状态对象
    def self.unavailable_state(reason)
      RuntimeCapabilityState.new(
        status: RuntimeCapabilityStatus::UNAVAILABLE,
        enabled: false,
        available: false,
        reason: reason
      )
    end

    # 根据启用状态和原因创建能力状态对象
    def self.state_from_enabled(enabled, disabled_reason, unavailable_reason)
      if enabled
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::UNAVAILABLE,
          enabled: true,
          available: false,
          reason: unavailable_reason
        )
      else
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::DISABLED,
          enabled: false,
          available: false,
          reason: disabled_reason
        )
      end
    end

    # 计算提供者能力状态：结合配置开关和提供者可用性
    def self.provider_capability_state(enabled, disabled_reason, available_provider, unavailable_reason)
      unless enabled
        return RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::DISABLED,
          enabled: false,
          available: false,
          reason: disabled_reason
        )
      end

      if available_provider
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::AVAILABLE,
          enabled: true,
          available: true
        )
      else
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::UNAVAILABLE,
          enabled: true,
          available: false,
          reason: unavailable_reason
        )
      end
    end

    # 计算 Web 能力状态：任一子能力（抓取或搜索）可用则整体可用
    def self.web_capability_state(enabled, fetch_state, search_state, reason)
      unless enabled
        return RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::DISABLED,
          enabled: false,
          available: false,
          reason: 'web access is disabled by config'
        )
      end

      if fetch_state.available || search_state.available
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::AVAILABLE,
          enabled: true,
          available: true
        )
      else
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::UNAVAILABLE,
          enabled: true,
          available: false,
          reason: reason || 'no web providers available'
        )
      end
    end

    # 计算技能能力状态：已发现技能数大于零则可用
    def self.skills_capability_state(enabled, discovered_skills, reason)
      unless enabled
        return RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::DISABLED,
          enabled: false,
          available: false,
          reason: 'Skills are disabled by config'
        )
      end

      if discovered_skills.positive?
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::AVAILABLE,
          enabled: true,
          available: true
        )
      else
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::UNAVAILABLE,
          enabled: true,
          available: false,
          reason: reason || 'no Skills discovered'
        )
      end
    end

    # 计算 MCP 能力状态：有已连接服务器则可用
    def self.mcp_capability_state(enabled, connected_servers, last_error)
      unless enabled
        return RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::DISABLED,
          enabled: false,
          available: false,
          reason: 'MCP is disabled by config'
        )
      end

      if connected_servers.positive?
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::AVAILABLE,
          enabled: true,
          available: true
        )
      else
        RuntimeCapabilityState.new(
          status: RuntimeCapabilityStatus::UNAVAILABLE,
          enabled: true,
          available: false,
          reason: last_error || 'no MCP servers connected'
        )
      end
    end

    # 验证 MCP 服务器配置的合法性
    # 返回值：错误消息数组，空数组表示验证通过
    def self.validate_mcp_server_config(config)
      errors = []

      if config.transport == McpTransportKind::STDIO && config.command.nil?
        errors << 'stdio MCP servers require command'
      end

      if %w[streamable-http sse].include?(config.transport) && config.url.nil?
        errors << "#{config.transport} MCP servers require url"
      end

      if config.url
        begin
          uri = ::URI.parse(config.url)
          errors << 'MCP server url must use http or https' unless %w[http https].include?(uri.scheme)
        rescue ::URI::InvalidURIError
          errors << 'MCP server url must be a valid URL'
        end
      end

      if config.trust_scope == McpTrustScope::WORKSPACE && config.trusted_workspace_roots.empty?
        errors << 'workspace-scoped MCP servers require at least one trusted workspace root'
      end

      errors
    end

    # 验证 MCP 搜索配置的合法性
    def self.validate_mcp_search_config(config)
      errors = []

      errors << 'topKDefault must be less than or equal to topKMax' if config.top_k_default > config.top_k_max

      errors
    end

    DEFAULT_DEEPFORGE_CAPABILITIES_CONFIG = build_default_capabilities_config
  end
end
