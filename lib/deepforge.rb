# frozen_string_literal: true

module DeepForge
  VERSION = '0.3.0'

  # --- Domain ---
  autoload :AgentThread,    'deepforge/domain/agent_thread'
  autoload :DialogueTurn,   'deepforge/domain/dialogue_turn'
  autoload :RuntimeEvent,   'deepforge/domain/runtime_event'
  autoload :HistoryItem,    'deepforge/domain/history_item'
  autoload :UsageSnapshot,  'deepforge/domain/usage_snapshot'
  autoload :Approval,       'deepforge/domain/approval'
  autoload :Session,        'deepforge/domain/session'
  autoload :ModelHistoryRepair, 'deepforge/domain/model_history_repair'
  autoload :RuntimeEventReducer, 'deepforge/domain/runtime_event_reducer'

  # --- Ports ---
  autoload :EventBus,           'deepforge/ports/event_bus'
  autoload :AgentThreadStore,   'deepforge/ports/agent_thread_store'
  autoload :SessionStore,       'deepforge/ports/session_store'
  autoload :ModelClient,        'deepforge/ports/model_client'
  autoload :ToolHost,           'deepforge/ports/tool_host'
  autoload :ApprovalGate,       'deepforge/ports/approval_gate'
  autoload :UserInputGate,      'deepforge/ports/user_input_gate'
  autoload :WorkspaceInspector, 'deepforge/ports/workspace_inspector'
  autoload :IdGenerator,        'deepforge/ports/id_generator'
  autoload :Clock,              'deepforge/ports/clock'
  autoload :WebProvider,        'deepforge/ports/web_provider'

  # --- Loop ---
  module Loop
    autoload :AgentLoop,             'deepforge/loop/agent_loop'
    autoload :ContextCompactor,      'deepforge/loop/compaction/compactor'
    autoload :ContextEstimator,      'deepforge/loop/compaction/estimator'
    autoload :CompactionMarker,      'deepforge/loop/compaction/marker'
    autoload :InflightTracker,       'deepforge/loop/inflight_tracker'
    autoload :SteeringQueue,         'deepforge/loop/steering_queue'
    autoload :ToolStormBreaker,      'deepforge/loop/tool_storm_breaker'
    autoload :ToolCallRepair,        'deepforge/loop/tool_call_repair'
    autoload :HistoryHealing,        'deepforge/loop/history_healing'
    autoload :RequestHistoryHygiene, 'deepforge/loop/request_history_hygiene'
    autoload :TokenEconomy,          'deepforge/loop/token_economy'
    autoload :AutoModelRouter,       'deepforge/loop/auto_model_router'
    autoload :ModelContextProfile,   'deepforge/loop/model_context_profile'
    autoload :ModelRequestEstimator, 'deepforge/loop/model_request_estimator'
    autoload :AppendOnlySessionLog,  'deepforge/loop/append_only_session_log'
    autoload :Pipeline,              'deepforge/loop/pipeline'
  end

  # --- Services ---
  autoload :AgentThreadService,     'deepforge/services/agent_thread_service'
  autoload :DialogueTurnService,    'deepforge/services/dialogue_turn_service'
  autoload :ReviewService,          'deepforge/services/review_service'
  autoload :UsageService,           'deepforge/services/usage_service'
  autoload :RuntimeEventRecorder,   'deepforge/services/runtime_event_recorder'

  # --- Server ---
  autoload :App, 'deepforge/server/app'

  module Server
    autoload :Runtime,          'deepforge/server/runtime'
    autoload :RuntimeHelpers,   'deepforge/server/runtime_helpers'
    autoload :NodeHttpServer,   'deepforge/server/node_http_server'
  end

  # --- Module-level autoloads (load sub-components eagerly) ---
  autoload :Review,    'deepforge/review'
  autoload :Shared,    'deepforge/shared'
  autoload :Telemetry, 'deepforge/telemetry'

  # --- Config ---
  module Config
    autoload :Config,            'deepforge/config/config'
    autoload :DeepForgeConfig,   'deepforge/config/deepforge_config'
    autoload :SecretRedaction,   'deepforge/config/secret_redaction'
  end

  # --- Prompt ---
  module Prompt
    autoload :SystemPrompt,          'deepforge/prompt/system_prompt'
    autoload :DeepForgeSystemPrompt, 'deepforge/prompt/deepforge_system_prompt'
  end
end

# Top-level constants (defined outside DeepForge namespace in source)
autoload :LruCache,               'deepforge/cache/lru_cache'
autoload :TtlLruCache,            'deepforge/cache/ttl_lru_cache'
autoload :ImmutablePrefixBuilder, 'deepforge/cache/immutable_prefix'
autoload :PrefixVolatility,       'deepforge/cache/prefix_volatility'
autoload :ToolCatalogFingerprint, 'deepforge/cache/tool_catalog_fingerprint'
autoload :MemoryStore,            'deepforge/memory/memory_store'
autoload :FileMemoryStore,        'deepforge/memory/memory_store'
