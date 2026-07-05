# frozen_string_literal: true

# 文件用途：运行时工厂模块，负责组装和初始化 DeepForge 服务运行时的所有组件
# 使用方法：调用 create_deepforge_serve_runtime 创建运行时实例，调用 start_deepforge_serve 启动服务

require 'fileutils'
require 'json'
require_relative 'node_http_server'
require_relative 'runtime_helpers'
# require_relative '../app' # Roda app - not used yet
require_relative '../adapters/memory/event_bus'
require_relative '../adapters/memory/approval_gate'
require_relative '../adapters/memory/user_input_gate'
require_relative '../adapters/random_id_generator'
require_relative '../adapters/file/agent_thread_store'
require_relative '../adapters/file/file_session_store'
require_relative '../adapters/hybrid/hybrid_thread_store'
require_relative '../adapters/hybrid/hybrid_session_store'
require_relative '../adapters/workspace/local_workspace_inspector'
require_relative '../contracts/capabilities'
require_relative '../loop/compaction/compactor'
require_relative '../loop/agent_loop'
require_relative '../adapters/model/deepseek_client'
require_relative '../adapters/tool/capability_registry'
require_relative '../loop/inflight_tracker'
require_relative '../loop/steering_queue'
require_relative '../adapters/tool/local_tool_host'
require_relative '../services/agent_thread_service'
require_relative '../services/dialogue_turn_service'
require_relative '../services/review_service'
require_relative '../services/usage_service'
require_relative '../services/runtime_event_recorder'
require_relative '../attachments/attachment_store'
require_relative '../skills/skill_runtime'
require_relative '../memory/memory_store'
require_relative '../delegation/delegation_runtime'

module DeepForge
  module Server
    # DeepForge 服务模式的运行时配置选项
    RuntimeOptions = Struct.new(
      :host, :port, :config_path, :data_dir, :runtime_token,
      :api_key, :base_url, :model, :approval_policy, :sandbox_mode,
      :token_economy_mode, :token_economy, :insecure, :models,
      :context_compaction, :runtime, :storage, :capabilities, :started_at,
      keyword_init: true
    )

    DEEPFORGE_SYSTEM_PROMPT = 'You are DeepForge, an AI assistant.'

    # 服务模式的组合根。这是唯一将具体适配器连接到端口的地方；
    # 领域、服务、循环和 HTTP 处理器通过构造函数注入保持可测试性。
    def self.create_deepforge_serve_runtime(options)
      FileUtils.mkdir_p(options.data_dir)

      # Create stores based on storage backend
      stores = RuntimeHelpers.create_persistent_stores(options.data_dir, options.storage)
      session_store = stores[:session_store]
      thread_store = stores[:thread_store]

      # Create services and adapters
      event_bus = DeepForge::Adapters::Memory::EventBus.new
      approval_gate = DeepForge::Adapters::Memory::ApprovalGate.new
      user_input_gate = DeepForge::Adapters::Memory::UserInputGate.new
      workspace_inspector = DeepForge::Adapters::Workspace::LocalWorkspaceInspector.new
      usage_service = DeepForge::Services::UsageService.new
      inflight = DeepForge::Loop::InflightTracker.new
      steering = DeepForge::Loop::SteeringQueue.new
      context_config = options.context_compaction || {}
      compactor = DeepForge::Loop::ContextCompactor.new(
        soft_threshold: context_config[:default_soft_threshold],
        hard_threshold: context_config[:default_hard_threshold]
      )
      token_economy = RuntimeHelpers.token_economy_config_for_options(options)
      ids = DeepForge::Adapters::RandomIdGenerator.new
      now_iso = -> { Time.now.utc.strftime('%FT%TZ') }
      allocate_seq = ->(thread_id) { event_bus.allocate_seq(thread_id) }

      events = DeepForge::Services::RuntimeEventRecorder.new(
        event_bus: event_bus,
        session_store: session_store,
        allocate_seq: allocate_seq,
        now_iso: now_iso
      )

      prefix = RuntimeHelpers.create_immutable_prefix(
        system_prompt: DEEPFORGE_SYSTEM_PROMPT,
        pinned_constraints: [
          'system: preserve user intent across compaction',
          'system: keep the HTTP/SSE contract stable for the GUI',
          'system: keep the stable DeepForge prefix byte-stable for prompt-cache reuse'
        ]
      )

      turn_service = DeepForge::Services::DialogueTurnService.new(
        thread_store: thread_store,
        session_store: session_store,
        events: events,
        inflight: inflight,
        steering: steering,
        compactor: compactor,
        ids: ids,
        now_iso: now_iso
      )

      thread_service = DeepForge::Services::AgentThreadService.new(
        thread_store: thread_store,
        session_store: session_store,
        events: events,
        ids: ids,
        now_iso: now_iso
      )

      RuntimeHelpers.seed_usage_carryover(thread_store, session_store, usage_service)

      model_client = DeepForge::Adapters::Model::DeepseekClient.new(
        base_url: options.base_url,
        api_key: options.api_key,
        model: options.model
      )

      model_profiles = RuntimeHelpers.model_context_profiles_from_config(
        context_compaction: options.context_compaction,
        models: options.models
      )

      review_service = DeepForge::Services::ReviewService.new(
        thread_store: thread_store,
        turns: turn_service,
        model: model_client,
        default_model: options.model,
        now_iso: now_iso,
        model_capabilities: ->(model) { RuntimeHelpers.model_capabilities_for_model(model, model_profiles) }
      )

      # Build tool providers
      mcp_providers = RuntimeHelpers.build_mcp_tool_providers(options.capabilities&.dig(:mcp))
      web_providers = RuntimeHelpers.build_web_tool_providers(options.capabilities&.dig(:web))
      skill_runtime = DeepForge::Skills::SkillRuntime.create(options.capabilities&.dig(:skills))

      attachment_store = if options.capabilities&.dig(:attachments, :enabled)
                           DeepForge::Attachments::FileAttachmentStore.new(
                             root_dir: File.join(options.data_dir, 'attachments'),
                             config: options.capabilities[:attachments],
                             now_iso: now_iso
                           )
                         end

      memory_store = if options.capabilities&.dig(:memory, :enabled)
                       ::FileMemoryStore.new(
                         root_dir: File.join(options.data_dir, 'memory'),
                         config: options.capabilities[:memory],
                         now_iso: now_iso
                       )
                     end

      cp_provider = DeepForge::Adapters::Tool::CapabilityToolProvider

      base_tool_providers = [
        cp_provider.new(
          id: 'builtin',
          kind: 'built-in',
          enabled: true,
          available: true,
          tools: RuntimeHelpers.build_default_local_tools
        ),
        *mcp_providers[:providers],
        *web_providers[:providers],
        *RuntimeHelpers.build_memory_tool_providers(memory_store)
      ]

      child_registry = DeepForge::Adapters::Tool::CapabilityRegistry.new(base_tool_providers)
      child_tool_host = DeepForge::Adapters::Tool::LocalToolHost.new(
        DeepForge::Adapters::Tool::LocalToolHostOptions.new(registry: child_registry, read_tracker: true)
      )

      delegation_runtime = if options.capabilities&.dig(:subagents, :enabled)
                             DeepForge::Delegation::DelegationRuntime.new(
                               config: options.capabilities[:subagents],
                               store: DeepForge::Delegation::FileDelegationStore.new(File.join(options.data_dir,
                                                                                               'child-runs')),
                               events: events,
                               now_iso: now_iso,
                               executor: RuntimeHelpers.create_child_agent_executor(
                                 model: model_client,
                                 tool_host: child_tool_host,
                                 prefix: prefix,
                                 default_model: options.model,
                                 models: options.models,
                                 context_compaction: options.context_compaction,
                                 approval_policy: options.approval_policy,
                                 sandbox_mode: options.sandbox_mode,
                                 model_capabilities: lambda { |model|
                                   RuntimeHelpers.model_capabilities_for_model(model, model_profiles)
                                 },
                                 skill_runtime: skill_runtime,
                                 token_economy: token_economy,
                                 memory_store: memory_store,
                                 now_iso: now_iso
                               ),
                               record_external_usage: ->(thread_id, usage) { usage_service.record(thread_id, usage) }
                             )
                           end

      capabilities = RuntimeHelpers.build_runtime_capability_manifest(
        config: options.capabilities,
        model: RuntimeHelpers.model_capabilities_for_model(options.model, model_profiles),
        mcp: {
          configuredServers: options.capabilities&.dig(:mcp, :servers)&.length || 0,
          connected_servers: mcp_providers[:connectedServers],
          tool_count: mcp_providers[:toolCount],
          lastError: mcp_providers[:diagnostics]&.find { |d| d[:lastError] }&.dig(:lastError),
          search: mcp_providers[:search]
        },
        web: {
          fetch_available: web_providers[:fetchAvailable],
          search_available: web_providers[:searchAvailable],
          provider: web_providers[:provider],
          reason: web_providers[:diagnostics]&.find { |d| d[:reason] }&.dig(:reason)
        },
        skills: {
          configuredRoots: options.capabilities&.dig(:skills, :roots)&.length || 0,
          discoveredSkills: skill_runtime.count,
          reason: skill_runtime.diagnostics[:validationErrors]&.first&.dig(:message)
        },
        attachments: { available: !attachment_store.nil? },
        memory: { available: !memory_store.nil? },
        subagents: { available: !delegation_runtime.nil? }
      )

      registry = DeepForge::Adapters::Tool::CapabilityRegistry.new([
                                                                     *base_tool_providers,
                                                                     cp_provider.new(
                                                                       id: 'goal',
                                                                       kind: 'gui',
                                                                       enabled: true,
                                                                       available: true,
                                                                       tools: RuntimeHelpers.build_goal_local_tools(thread_service)
                                                                     ),
                                                                     cp_provider.new(
                                                                       id: 'todo',
                                                                       kind: 'gui',
                                                                       enabled: true,
                                                                       available: true,
                                                                       tools: RuntimeHelpers.build_todo_local_tools(thread_service)
                                                                     ),
                                                                     *RuntimeHelpers.build_delegation_tool_providers(delegation_runtime)
                                                                   ])

      tool_host = DeepForge::Adapters::Tool::LocalToolHost.new(
        DeepForge::Adapters::Tool::LocalToolHostOptions.new(registry: registry, read_tracker: true)
      )

      loop_instance = DeepForge::Loop::AgentLoop.new(
        thread_store: thread_store,
        session_store: session_store,
        approval_gate: approval_gate,
        user_input_gate: user_input_gate,
        model: model_client,
        tool_host: tool_host,
        usage: usage_service,
        events: events,
        turns: turn_service,
        inflight: inflight,
        steering: steering,
        compactor: compactor,
        prefix: prefix,
        ids: ids,
        now_iso: now_iso,
        model_capabilities: ->(model) { RuntimeHelpers.model_capabilities_for_model(model, model_profiles) },
        skill_runtime: skill_runtime,
        token_economy: token_economy,
        memory_store: memory_store
      )

      started_at = now_iso.call

      {
        thread_service: thread_service,
        turn_service: turn_service,
        review_service: review_service,
        usage_service: usage_service,
        event_bus: event_bus,
        session_store: session_store,
        events: events,
        approval_gate: approval_gate,
        user_input_gate: user_input_gate,
        workspace_inspector: workspace_inspector,
        tool_host: tool_host,
        attachment_store: attachment_store,
        memory_store: memory_store,
        run_turn: ->(thread_id, turn_id) { loop_instance.run_turn(thread_id, turn_id) },
        run_review: ->(input) { review_service.run_review(input) },
        runtime_token: options.runtime_token,
        insecure: options.insecure,
        allocate_seq: allocate_seq,
        now_iso: now_iso,
        info: lambda {
          {
            host: options.host,
            port: options.port,
            config_path: options.config_path,
            data_dir: options.data_dir,
            model: options.model,
            approval_policy: options.approval_policy,
            sandbox_mode: options.sandbox_mode,
            token_economy_mode: options.token_economy_mode,
            insecure: options.insecure,
            started_at: started_at,
            pid: Process.pid,
            capabilities: capabilities.respond_to?(:to_h) ? capabilities.to_h : capabilities
          }
        },
        toolDiagnostics: lambda {
          mem_diags = memory_store&.diagnostics
          att_diags = attachment_store&.diagnostics
          {
            providers: registry.diagnostics,
            mcpServers: mcp_providers[:diagnostics],
            mcpSearch: mcp_providers[:search],
            webProviders: web_providers[:diagnostics],
            skills: skill_runtime.diagnostics,
            attachments: if att_diags
                           { enabled: att_diags[:enabled], root_dir: att_diags[:root_dir],
                             count: att_diags[:count], totalBytes: att_diags[:total_bytes] }
                         else
                           { enabled: false, root_dir: '', count: 0,
                             totalBytes: 0 }
                         end,
            memory: if mem_diags
                      { enabled: mem_diags[:enabled], root_dir: mem_diags[:root_dir],
                        activeCount: mem_diags[:active_count], tombstoneCount: mem_diags[:tombstone_count], lastInjectedIds: mem_diags[:last_injected_ids] }
                    else
                      {
                        enabled: false, root_dir: '', activeCount: 0, tombstoneCount: 0, lastInjectedIds: []
                      }
                    end
          }
        },
        shutdown: lambda {
          mcp_providers[:close]&.call
          stores[:shutdown]&.call
        }
      }
    end

    # 启动 DeepForge 服务运行时
    # @param options [RuntimeOptions] 运行时配置选项
    # @return [Hash] 服务器句柄，包含 :server、:host、:port、:runtime、:close
    def self.start_deepforge_serve(options)
      runtime = create_deepforge_serve_runtime(options)
      server = start_node_http_server(host: options.host, port: options.port)

      {
        server: server.server,
        host: server.host,
        port: server.port,
        runtime: runtime,
        close: lambda {
          server.close
          runtime[:shutdown]&.call
        }
      }
    end
  end
end
