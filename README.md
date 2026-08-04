# DeepForge

Local HTTP/SSE agent runtime for AI-powered GUI applications.

DeepForge is a Ruby-based agent runtime built with Clean Architecture (Domain-Driven Design + Ports & Adapters). It powers AI-powered GUI applications by managing conversational agent loops with tool orchestration, context compaction, streaming events, and a pluggable capability system.

[![Ruby](https://img.shields.io/badge/Ruby-3.2+-red)](https://ruby-lang.org)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-2047-green)]()
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20%7C%20DDD%20%7C%20Ports%20%26%20Adapters-blueviolet)]()

---

## Requirements

- Ruby >= 3.2.0
- Bundler

## Installation

```bash
git clone https://github.com/benjis/DeepForge
cd deepforge
bundle install
```

## Quick Start

```bash
# Start the server
bundle exec ruby -Ilib lib/deepforge/cli/serve_entry.rb serve \
  --data-dir /path/to/data \
  --api-key sk-your-deepseek-api-key

# Enable insecure mode for local development (no bearer token)
bundle exec ruby -Ilib lib/deepforge/cli/serve_entry.rb serve \
  --data-dir /tmp/deepforge-data \
  --insecure
```

## Configuration

### CLI Options

```
deepforge serve [options]

Options:
  --config <path>          JSON config file (default: {data-dir}/config.json)
  --host <host>            Bind address (default: 127.0.0.1)
  --port <port>            HTTP port (default: 8899)
  --data-dir <path>        Root directory for threads, events, and usage
  --runtime-token <token>  Bearer token for /v1/* requests
  --api-key <key>          DeepSeek-compatible API key
  --base-url <url>         DeepSeek-compatible base URL (default: https://api.deepseek.com/beta)
  --model <model>          Default model id (default: deepseek-chat)
  --approval-policy <p>    on-request | untrusted | never | auto | suggest (default: on-request)
  --sandbox-mode <mode>    read-only | workspace-write | danger-full-access | external-sandbox
  --token-economy          Compress safe tool context before model calls
  --insecure               Disable bearer token check (local dev only)
  --storage-backend <b>    hybrid | file (default: hybrid)
  --sqlite-path <path>     SQLite index path for hybrid storage
```

### Environment Variables

| Variable | Description |
|---|---|
| `DEEPFORGE_HOST` | Bind address |
| `DEEPFORGE_PORT` | HTTP port |
| `DEEPFORGE_DATA_DIR` | Data directory |
| `DEEPFORGE_RUNTIME_TOKEN` | Bearer token |
| `DEEPSEEK_API_KEY` | API key |
| `DEEPFORGE_BASE_URL` | Base URL for model API |
| `DEEPFORGE_MODEL` | Default model |
| `DEEPFORGE_STORAGE_BACKEND` | Storage backend (hybrid/file) |
| `DEEPFORGE_TOKEN_ECONOMY_MODE` | Token economy toggle |

### JSON Config File

Place a `config.json` in your `--data-dir`:

```json
{
  "serve": {
    "host": "127.0.0.1",
    "port": 19946,
    "model": "deepseek-chat",
    "apiKey": "sk-...",
    "storage": { "backend": "hybrid" },
    "capabilities": {
      "attachments": { "enabled": true },
      "memory": { "enabled": true },
      "subagents": { "enabled": true, "maxParallel": 3 }
    }
  }
}
```

---

## Architecture

DeepForge follows **Clean Architecture** with strict separation of concerns:

```
┌─────────────────────────────────────────────────────┐
│                    Server (Roda)                     │
│    HTTP Routes  ·  SSE Streaming  ·  Auth Middleware │
├─────────────────────────────────────────────────────┤
│                 Application Services                 │
│  AgentThreadService  ·  DialogueTurnService          │
│  UsageService        ·  ReviewService                │
├─────────────────────────────────────────────────────┤
│              Agent Loop  ·  Pipeline                 │
│  Setup → Steering → History → Router → Context       │
│  → Catalog → Request → Response → Dispatch → Budget  │
├─────────────────────────────────────────────────────┤
│                Ports (Abstract Interfaces)           │
│  EventBus  ·  Store  ·  ModelClient  ·  ToolHost     │
│  ApprovalGate  ·  IdGenerator  ·  Clock              │
├─────────────────────────────────────────────────────┤
│              Adapters (Concrete Implementations)     │
│  Memory/   File/   Model/   Tool/   Workspace/       │
├─────────────────────────────────────────────────────┤
│                 Domain (Pure Ruby)                   │
│  AgentThread  ·  DialogueTurn  ·  RuntimeEvent       │
│  HistoryItem  ·  UsageSnapshot  ·  Approval          │
└─────────────────────────────────────────────────────┘
```

### Layer Responsibilities

- **Domain** — Pure Ruby data structures with no dependencies or side effects
- **Ports** — Abstract interfaces (base classes with `NotImplementedError`) defining the contracts
- **Adapters** — Concrete implementations of ports (in-memory for testing, file/hybrid for production)
- **Services** — Application orchestration: thread CRUD, turn management, usage tracking
- **Loop** — The agent pipeline: 11 sequential pipeline stages orchestrated by `AgentLoop`
- **Server** — Roda HTTP application with SSE streaming, routes, and auth middleware

---

## Project Structure

```
lib/deepforge/
├── deepforge.rb                  # Entry point with autoload declarations
├── domain/                       # Pure domain models (no dependencies)
│   ├── agent_thread.rb           # Conversation thread
│   ├── dialogue_turn.rb          # Single turn within a thread
│   ├── runtime_event.rb          # Runtime event
│   ├── history_item.rb           # Message/item in conversation history
│   ├── usage_snapshot.rb         # Token and cost usage snapshot
│   ├── session.rb                # Session state
│   ├── approval.rb               # Approval request
│   └── model_history_repair.rb   # History repair logic
│
├── ports/                        # Abstract interfaces
│   ├── event_bus.rb              # Event publish/subscribe contract
│   ├── agent_thread_store.rb     # Thread persistence contract
│   ├── session_store.rb          # Session persistence contract
│   ├── model_client.rb           # Model API contract
│   ├── tool_host.rb              # Tool execution contract
│   ├── approval_gate.rb          # Approval gate contract
│   ├── user_input_gate.rb        # User input contract
│   ├── workspace_inspector.rb    # Workspace inspection contract
│   ├── id_generator.rb           # ID generation contract
│   ├── clock.rb                  # Time provider contract
│   └── web_provider.rb           # Web fetch/search contract
│
├── adapters/                     # Concrete implementations
│   ├── memory/                   # In-memory adapters (testing)
│   ├── file/                     # File-based persistence
│   ├── model/                    # DeepSeek-compatible model client
│   ├── tool/                     # Tool host & capability registry
│   ├── workspace/                # Local workspace inspector
│   └── random_id_generator.rb    # UUID-based ID generator
│
├── loop/                         # Agent loop & pipeline
│   ├── agent_loop.rb             # Pipeline orchestrator (~200 lines)
│   ├── pipeline.rb               # 11-stage pipeline framework
│   ├── pipeline/                 # Pipeline stages
│   │   ├── setup.rb              # Abort controllers & goal timers
│   │   ├── steering_drain.rb     # Pending steering messages
│   │   ├── history_loader.rb     # Load & heal conversation history
│   │   ├── model_router.rb       # Model selection & routing
│   │   ├── context_builder.rb    # Skills, memories, instructions
│   │   ├── tool_catalog_manager.rb  # Tool fingerprint & drift
│   │   ├── request_builder.rb    # Request assembly & token economy
│   │   ├── response_handler.rb   # Stream response processing
│   │   ├── tool_dispatcher.rb    # Tool call dispatch & parallel exec
│   │   ├── budget_gate.rb        # Cost budget enforcement
│   │   └── goal_manager.rb       # Goal elapsed timer finalization
│   ├── compaction/               # Context window management
│   │   ├── compactor.rb          # Compaction planning & execution
│   │   ├── estimator.rb          # Token estimation
│   │   └── marker.rb             # Compaction markers
│   ├── token_economy.rb          # Token optimization
│   ├── history_healing.rb        # History repair
│   ├── tool_call_repair.rb       # Tool argument repair
│   ├── steering_queue.rb         # Steering queue
│   ├── inflight_tracker.rb       # In-flight request tracking
│   └── ...                       # Additional loop utilities
│
├── services/                     # Application services
│   ├── agent_thread_service.rb   # Thread CRUD
│   ├── dialogue_turn_service.rb  # Turn lifecycle
│   ├── review_service.rb         # Code review
│   ├── usage_service.rb          # Usage tracking
│   └── runtime_event_recorder.rb # Event recording
│
├── server/                       # HTTP & SSE server
│   ├── app.rb                    # Roda application (all routes)
│   ├── runtime.rb                # DI composition root
│   ├── middleware/               # Rack middleware
│   │   ├── auth.rb               # Bearer token auth
│   │   └── sse.rb                # SSE helpers
│   ├── node_http_server.rb       # Falcon server startup
│   ├── runtime_helpers.rb        # DI helper utilities
│   └── routes/                   # Route handler modules
│       ├── threads.rb / turns.rb / events.rb ...
│       └── approvals.rb / memory.rb / usage.rb ...
│
├── contracts/                    # Data contract definitions (Structs)
├── config/                       # Configuration loading
├── cache/                        # Caching (LRU, TTL, immutable prefix)
├── telemetry/                    # Usage & cache telemetry
├── prompt/                       # System prompt management
├── cli/                          # CLI entry points
├── delegation/                   # Child agent execution
├── memory/                       # Memory store (embeddings-based retrieval)
├── attachments/                  # File attachment store
├── skills/                       # Skill runtime
├── shared/                       # Shared entities (GUI plan, todos)
└── utils/                        # General utilities
```

---

## API Endpoints

All `/v1/*` endpoints require `Authorization: Bearer <runtime-token>` header (unless `--insecure` is set).

### Health

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check (unauthenticated) |

### Runtime

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/runtime/info` | Runtime diagnostics (version, config, capabilities) |
| `GET` | `/v1/runtime/tools` | Tool diagnostics (registered tool providers) |

### Threads

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/threads` | List all threads |
| `POST` | `/v1/threads` | Create a new thread |
| `GET` | `/v1/threads/:id` | Get thread details |
| `PATCH` | `/v1/threads/:id` | Update thread metadata |
| `DELETE` | `/v1/threads/:id` | Delete a thread |
| `POST` | `/v1/threads/:id/fork` | Fork a thread |

### Goals & Todos

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/threads/:id/goal` | Get thread goal |
| `POST` | `/v1/threads/:id/goal` | Set/update thread goal |
| `DELETE` | `/v1/threads/:id/goal` | Clear thread goal |
| `GET` | `/v1/threads/:id/todos` | Get thread todo list |
| `POST` | `/v1/threads/:id/todos` | Set thread todo list |
| `DELETE` | `/v1/threads/:id/todos` | Clear thread todo list |

### Turns

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/threads/:id/turns` | Start a new turn (fires agent loop) |
| `GET` | `/v1/threads/:id/turns/:turnId` | Get turn details |
| `POST` | `/v1/threads/:id/turns/:turnId/steer` | Inject a steering message |
| `POST` | `/v1/threads/:id/turns/:turnId/interrupt` | Interrupt a running turn |
| `POST` | `/v1/threads/:id/compact` | Trigger manual context compaction |

### Events (SSE)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/threads/:id/events` | Server-Sent Events stream |

Streams real-time events: `assistant_text_delta`, `assistant_reasoning_delta`, `tool_call_ready`, `tool_result`, `usage`, `pipeline_stage`, `error`.

### Review

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/threads/:id/review` | Start a code review |

### Attachments

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/attachments` | Upload an attachment |
| `GET` | `/v1/attachments/diagnostics` | Attachment store diagnostics |
| `GET` | `/v1/attachments/:id` | Get attachment metadata |
| `GET` | `/v1/attachments/:id/content` | Get attachment content |

### Memory

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/memory` | List memories |
| `POST` | `/v1/memory` | Create a memory |
| `GET` | `/v1/memory/diagnostics` | Memory store diagnostics |
| `PATCH` | `/v1/memory/:id` | Update a memory |
| `DELETE` | `/v1/memory/:id` | Delete a memory |

### Workspace

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/workspace/status` | Get workspace status (git info, etc.) |

### Usage

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/usage` | Get usage statistics |

### Approvals & User Input

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/approvals/:id` | Decide on a pending approval |
| `POST` | `/v1/user-input/:id` | Resolve a pending user input request |

### Sessions

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/sessions/:id/resume-thread` | Resume a session |

---

## Key Components

### Agent Loop Pipeline

The `AgentLoop` orchestrates a sequential pipeline of 11 stages:

1. **Setup** — Validate abort signal, initialize storm breaker, start goal timer
2. **Steering Drain** — Inject any pending steering messages as user input
3. **History Loader** — Load and heal conversation history from session store
4. **Model Router** — Resolve which model to use (fixed or auto-routed)
5. **Context Builder** — Gather skills, memories, goals, and instructions
6. **Tool Catalog Manager** — Fingerprint tools and detect catalog drift
7. **Request Builder** — Assemble model request with token economy optimization
8. **Response Handler** — Process streaming model response (text, reasoning, tool calls)
9. **Tool Dispatcher** — Execute tool calls with parallel read-only optimization and storm breaker
10. **Budget Gate** — Enforce cost budget limits with warnings
11. **Goal Manager** — Track goal elapsed time

### Tool System

Tools are organized into providers registered with the `CapabilityRegistry`:

| Provider | Type | Examples |
|---|---|---|
| Built-in | `built-in` | `read`, `write`, `edit`, `grep`, `find`, `ls`, `bash`, `truncate` |
| MCP | `mcp` | Any MCP-compatible server tools |
| Web | `web` | `web_fetch`, `web_search` |
| Memory | `memory` | `memory_store` |
| Goal | `gui` | `get_goal`, `update_goal` |
| Todo | `gui` | `todo_list`, `todo_write` |
| Delegation | `delegation` | `delegate_task` |

### Storage

Two backends available:

- **hybrid** (default) — JSON files on disk with SQLite index for efficient listing
- **file** — Pure JSON file-based storage

---

## Testing

```bash
# Run full suite
bundle exec rspec

# Run with specific seed
bundle exec rspec --seed 42

# Run specific files
bundle exec rspec spec/loop/
bundle exec rspec spec/services/
```

2047 examples, 0 failures, 15 pending.

---

## Development

### Code Layout Conventions

- `domain/` — Pure Ruby, no `require_relative` dependencies on other modules
- `ports/` — Abstract base classes raising `NotImplementedError`
- `adapters/` — Concrete implementations that inherit from ports
- Each file has a single responsibility
- Autoload declarations in `index.rb` files for lazy loading

### Adding a New Tool

1. Define the tool handler in `adapters/tool/`
2. Register it with `CapabilityRegistry` in `server/runtime.rb`
3. Define its schema in the provider configuration

---

## License

MIT License. See [LICENSE](LICENSE) for details.
