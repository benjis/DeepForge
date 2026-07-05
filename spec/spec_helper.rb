# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)

# Load modules individually to avoid circular dependency issues in the full require
%w[
  deepforge/utils/key_normalizer
  deepforge/ports/clock deepforge/ports/id_generator deepforge/ports/event_bus
  deepforge/ports/approval_gate deepforge/ports/session_store deepforge/ports/agent_thread_store
  deepforge/ports/model_client deepforge/ports/tool_host deepforge/ports/user_input_gate
  deepforge/ports/web_provider deepforge/ports/workspace_inspector
  deepforge/contracts/approvals deepforge/contracts/attachments deepforge/contracts/capabilities
  deepforge/contracts/errors deepforge/contracts/events deepforge/contracts/items
  deepforge/contracts/memory deepforge/contracts/policy deepforge/contracts/review
  deepforge/contracts/runtime_info deepforge/contracts/threads deepforge/contracts/turns
  deepforge/contracts/usage deepforge/contracts/workspace
  deepforge/domain/approval deepforge/domain/runtime_event deepforge/domain/history_item
  deepforge/domain/model_history_repair deepforge/domain/runtime_event_reducer
  deepforge/domain/session deepforge/domain/agent_thread deepforge/domain/dialogue_turn deepforge/domain/usage_snapshot
  deepforge/cache/immutable_prefix deepforge/cache/lru_cache deepforge/cache/ttl_lru_cache
  deepforge/cache/prefix_volatility deepforge/cache/tool_catalog_fingerprint
  deepforge/memory/memory_store
  deepforge/config/config deepforge/config/deepforge_config deepforge/config/secret_redaction
  deepforge/attachments/attachment_store
  deepforge/telemetry/cache_telemetry deepforge/telemetry/usage_counter
  deepforge/adapters/in_memory/approval_gate deepforge/adapters/in_memory/event_bus
  deepforge/adapters/in_memory/session_store deepforge/adapters/memory/agent_thread_store
  deepforge/adapters/in_memory/user_input_gate
  deepforge/adapters/model/deepseek_compat_model_client deepforge/adapters/model/deepseek_pricing
  deepforge/adapters/model/model_error_probe deepforge/adapters/model/tool_argument_repair
  deepforge/adapters/file/atomic_write deepforge/adapters/file/file_session_store
  deepforge/adapters/file/agent_thread_store
  # deepforge/adapters/hybrid/hybrid_session_store deepforge/adapters/hybrid/hybrid_thread_store
  deepforge/adapters/workspace/local_workspace_inspector
  deepforge/adapters/tool/local_tool_host deepforge/adapters/tool/builtin_tools
  deepforge/adapters/tool/builtin_tool_types deepforge/adapters/tool/builtin_tool_utils
  deepforge/adapters/tool/builtin_tool_operations deepforge/adapters/tool/capability_registry
  deepforge/adapters/tool/bash deepforge/adapters/tool/read deepforge/adapters/tool/write
  deepforge/adapters/tool/edit deepforge/adapters/tool/edit_diff deepforge/adapters/tool/find
  deepforge/adapters/tool/grep deepforge/adapters/tool/ls deepforge/adapters/tool/truncate
  deepforge/adapters/tool/read_tracker deepforge/adapters/tool/output_accumulator
  deepforge/adapters/tool/file_mutation_queue deepforge/adapters/tool/tool_hooks
  deepforge/adapters/tool/tool_rate_limit deepforge/adapters/tool/mcp_tool_provider
  deepforge/adapters/tool/mcp_tool_search deepforge/adapters/tool/web_tool_provider
  deepforge/adapters/tool/memory_tool_provider deepforge/adapters/tool/create_plan_tool
  deepforge/adapters/tool/delegation_tool_provider deepforge/adapters/tool/goal_tools
  deepforge/adapters/tool/todo_tools deepforge/adapters/tool/builtin_bash_tool
  deepforge/adapters/tool/builtin_file_tools deepforge/adapters/tool/builtin_read_tool
  deepforge/adapters/tool/builtin_search_tools
  deepforge/review/review_prompt deepforge/review/review_output
  deepforge/review/git_review_target
  deepforge/prompt/system_prompt deepforge/prompt/deepforge_system_prompt
  deepforge/shared/gui_plan deepforge/shared/todos
  deepforge/server/middleware/auth deepforge/server/response deepforge/server/read_json_body
  # deepforge/server/router deepforge/server/sse deepforge/server/runtime_helpers
  # deepforge/server/runtime
  # deepforge/server/routes/index deepforge/server/routes/health deepforge/server/routes/threads
  # deepforge/server/routes/turns deepforge/server/routes/events deepforge/server/routes/approvals
  # deepforge/server/routes/user_inputs deepforge/server/routes/sessions deepforge/server/routes/usage
  # deepforge/server/routes/runtime_info deepforge/server/routes/attachments
  # deepforge/server/routes/memory deepforge/server/routes/workspace deepforge/server/routes/review
  # deepforge/server/routes/runtime_error deepforge/server/routes/key_transform
  # deepforge/server/app
  # deepforge/services/runtime_event_recorder deepforge/services/turn_service
  # deepforge/services/thread_service deepforge/services/usage_service deepforge/services/review_service
  # deepforge/skills/skill_runtime
  # deepforge/cli/cli_options deepforge/cli/serve deepforge/cli/serve_entry deepforge/cli/agent_cli
  # deepforge/delegation/child_agent_executor deepforge/delegation/delegation_runtime
  deepforge/loop/compaction/estimator deepforge/loop/compaction/marker
  deepforge/loop/model_context_profile deepforge/loop/compaction/compactor
  deepforge/loop/inflight_tracker deepforge/loop/steering_queue
  deepforge/loop/token_economy deepforge/loop/request_history_hygiene
  deepforge/loop/model_request_estimator deepforge/loop/auto_model_router
  deepforge/loop/tool_storm_breaker deepforge/loop/history_healing deepforge/loop/tool_call_repair
  deepforge/loop/agent_loop deepforge/loop/compaction_history deepforge/loop/compaction_summary
  deepforge/loop/session_summary deepforge/loop/title_generator deepforge/loop/reasoning_effort
  deepforge/loop/append_only_session_log deepforge/loop/goal_resume_coordinator
  deepforge/loop/tool_result_image
].each do |mod|
  require mod
rescue StandardError, LoadError, NameError, SyntaxError
  # skip modules with optional dependencies
end

# DeepForge::Adapters::FileStore no longer shadows ::File (was renamed from File)

require 'json'
require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'base64'
require 'uri'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed
end
