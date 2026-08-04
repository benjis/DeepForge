# DeepForge

AI GUI 的本地 HTTP/SSE Agent 运行时

DeepForge 是一个基于 Ruby 的 Agent 运行时，采用 Clean Architecture（领域驱动设计 + 端口与适配器模式）构建。它为 AI GUI 应用提供对话式 Agent 循环，支持工具编排、上下文压缩、流式事件以及可插拔的能力系统。

[![Ruby](https://img.shields.io/badge/Ruby-3.2+-red)](https://ruby-lang.org)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-2047-green)]()
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20%7C%20DDD%20%7C%20Ports%20%26%20Adapters-blueviolet)]()

---

## 环境要求

- Ruby >= 3.2.0
- Bundler

## 安装

```bash
git clone https://github.com/benjis/DeepForge.git
cd DeepForge
bundle install
```

## 快速开始

```bash
# 启动服务器
bundle exec ruby -Ilib lib/deepforge/cli/serve_entry.rb serve \
  --data-dir /path/to/data \
  --api-key sk-your-deepseek-api-key

# 本地开发模式（跳过 Bearer Token 认证）
bundle exec ruby -Ilib lib/deepforge/cli/serve_entry.rb serve \
  --data-dir /tmp/deepforge-data \
  --insecure
```

## 配置

### CLI 选项

```
deepforge serve [options]

Options:
  --config <path>          配置文件路径（默认：{data-dir}/config.json）
  --host <host>            绑定地址（默认：127.0.0.1）
  --port <port>            HTTP 端口（默认：8899）
  --data-dir <path>        线程、事件和使用量数据根目录
  --runtime-token <token>  用于 /v1/* 接口的 Bearer Token
  --api-key <key>          DeepSeek 兼容 API Key
  --base-url <url>         DeepSeek 兼容基础 URL（默认：https://api.deepseek.com/beta）
  --model <model>          默认模型 ID（默认：deepseek-chat）
  --approval-policy <p>    审批策略：on-request | untrusted | never | auto | suggest
  --sandbox-mode <mode>    read-only | workspace-write | danger-full-access | external-sandbox
  --token-economy          在模型调用前压缩安全的工具上下文
  --insecure               禁用 Bearer Token 认证（仅本地开发）
  --storage-backend <b>    存储后端：hybrid | file（默认：hybrid）
  --sqlite-path <path>     hybrid 存储的 SQLite 索引文件路径
```

### 环境变量

| 变量 | 说明 |
|---|---|
| `DEEPFORGE_HOST` | 绑定地址 |
| `DEEPFORGE_PORT` | HTTP 端口 |
| `DEEPFORGE_DATA_DIR` | 数据目录 |
| `DEEPFORGE_RUNTIME_TOKEN` | Bearer Token |
| `DEEPSEEK_API_KEY` | API Key |
| `DEEPFORGE_BASE_URL` | 模型 API 基础 URL |
| `DEEPFORGE_MODEL` | 默认模型 |
| `DEEPFORGE_STORAGE_BACKEND` | 存储后端（hybrid/file） |
| `DEEPFORGE_TOKEN_ECONOMY_MODE` | Token 经济开关 |

### JSON 配置文件

在 `--data-dir` 目录下放置 `config.json`：

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

## 架构

DeepForge 采用 **Clean Architecture** 严格分层：

```
+-------------------------------------------------------+
|                    Server (Roda HTTP)                  |
|    HTTP 路由  .  SSE 流式推送  .  认证中间件            |
+-------------------------------------------------------+
|                  应用服务 (Services)                    |
|  AgentThreadService  .  DialogueTurnService            |
|  UsageService        .  ReviewService                  |
+-------------------------------------------------------+
|             Agent 循环  .  管道 (Pipeline)              |
|  Setup -> Steering -> History -> Router -> Context     |
|  -> Catalog -> Request -> Response -> Dispatch -> Budget|
+-------------------------------------------------------+
|               端口接口 (Ports)                          |
|  EventBus  .  Store  .  ModelClient  .  ToolHost       |
|  ApprovalGate  .  IdGenerator  .  Clock                |
+-------------------------------------------------------+
|             适配器实现 (Adapters)                       |
|  Memory/   File/   Model/   Tool/   Workspace/         |
+-------------------------------------------------------+
|                领域层 (Domain)                          |
|  AgentThread  .  DialogueTurn  .  RuntimeEvent         |
|  HistoryItem  .  UsageSnapshot  .  Approval            |
+-------------------------------------------------------+
```

### 各层职责

- **Domain** --- 纯 Ruby 数据结构。无外部依赖，无副作用
- **Ports** --- 抽象接口（基类 + NotImplementedError），定义契约
- **Adapters** --- 端口的具体实现（内存版用于测试，文件/hybrid 版用于生产）
- **Services** --- 应用编排：线程 CRUD、轮次管理、使用量追踪
- **Loop** --- Agent 管道：11 个顺序执行的管道阶段，由 AgentLoop 编排
- **Server** --- Roda HTTP 应用 + SSE 流式推送 + 路由 + 认证中间件

---

## 项目结构

```
lib/deepforge/
+-- deepforge.rb                  # 入口（autoload 延迟加载）
+-- domain/                       # 纯领域模型（无依赖）
|   +-- agent_thread.rb           # 对话线程
|   +-- dialogue_turn.rb          # 单次对话轮次
|   +-- runtime_event.rb          # 运行时事件
|   +-- history_item.rb           # 对话历史条目
|   +-- usage_snapshot.rb         # Token 用量快照
|   +-- session.rb                # 会话状态
|   +-- approval.rb               # 审批请求
|   +-- model_history_repair.rb   # 历史修复逻辑
|
+-- ports/                        # 抽象接口
|   +-- event_bus.rb              # 事件发布/订阅契约
|   +-- agent_thread_store.rb     # 线程持久化契约
|   +-- session_store.rb          # 会话持久化契约
|   +-- model_client.rb           # 模型 API 契约
|   +-- tool_host.rb              # 工具执行契约
|   +-- approval_gate.rb          # 审批门控契约
|   +-- user_input_gate.rb        # 用户输入契约
|   +-- workspace_inspector.rb    # 工作区检查契约
|   +-- id_generator.rb           # ID 生成契约
|   +-- clock.rb                  # 时间提供契约
|   +-- web_provider.rb           # 网页抓取/搜索契约
|
+-- adapters/                     # 具体实现
|   +-- memory/                   # 内存适配器（测试用）
|   +-- file/                     # 文件持久化
|   +-- model/                    # DeepSeek 兼容模型客户端
|   +-- tool/                     # 工具宿主 & 能力注册表
|   +-- workspace/                # 本地工作区检查器
|   +-- random_id_generator.rb    # UUID ID 生成器
|
+-- loop/                         # Agent 循环 & 管道
|   +-- agent_loop.rb             # 管道编排器（~200 行）
|   +-- pipeline.rb               # 11 阶段管道框架
|   +-- pipeline/                 # 管道各阶段
|   |   +-- setup.rb              # 中止控制器 & 目标计时
|   |   +-- steering_drain.rb     # 待处理引导消息
|   |   +-- history_loader.rb     # 加载 & 修复对话历史
|   |   +-- model_router.rb       # 模型选择 & 路由
|   |   +-- context_builder.rb    # 技能、记忆、指令组装
|   |   +-- tool_catalog_manager.rb  # 工具指纹 & 漂移检测
|   |   +-- request_builder.rb    # 请求组装 & Token 经济
|   |   +-- response_handler.rb   # 流式响应处理
|   |   +-- tool_dispatcher.rb    # 工具调用分发 & 并行执行
|   |   +-- budget_gate.rb        # 成本预算执行
|   |   +-- goal_manager.rb       # 目标计时器终结
|   +-- compaction/               # 上下文窗口管理
|   |   +-- compactor.rb          # 压缩规划 & 执行
|   |   +-- estimator.rb          # Token 估算
|   |   +-- marker.rb             # 压缩标记
|   +-- token_economy.rb          # Token 优化
|   +-- history_healing.rb        # 历史修复
|   +-- tool_call_repair.rb       # 工具参数修复
|   +-- steering_queue.rb         # 引导队列
|   +-- inflight_tracker.rb       # 飞行中请求追踪
|
+-- services/                     # 应用服务
|   +-- agent_thread_service.rb   # 线程 CRUD
|   +-- dialogue_turn_service.rb  # 轮次生命周期
|   +-- review_service.rb         # 代码审查
|   +-- usage_service.rb          # 用量追踪
|   +-- runtime_event_recorder.rb # 事件记录
|
+-- server/                       # HTTP & SSE 服务器
|   +-- app.rb                    # Roda 应用（全部路由）
|   +-- runtime.rb                # 依赖注入组合根
|   +-- middleware/               # Rack 中间件
|   |   +-- auth.rb               # Bearer Token 认证
|   |   +-- sse.rb                # SSE 辅助
|   +-- node_http_server.rb       # Falcon 服务器启动
|   +-- runtime_helpers.rb        # DI 辅助工具
|   +-- routes/                   # 路由处理器模块
|       +-- threads.rb / turns.rb / events.rb ...
|       +-- approvals.rb / memory.rb / usage.rb ...
|
+-- contracts/                    # 数据契约定义（Structs）
+-- config/                       # 配置加载
+-- cache/                        # 缓存（LRU, TTL, 不可变前缀）
+-- telemetry/                    # 用量 & 缓存遥测
+-- prompt/                       # 系统提示词管理
+-- cli/                          # CLI 入口
+-- delegation/                   # 子代理执行
+-- memory/                       # 记忆存储（基于 Embedding 检索）
+-- attachments/                  # 文件附件存储
+-- skills/                       # 技能运行时
+-- shared/                       # 共享实体（GUI plan、todos）
+-- utils/                        # 通用工具
```

---

## API 端点

所有 /v1/* 端点需要 Authorization: Bearer <runtime-token> 请求头（除非启用 --insecure）。

### 健康检查

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /health | 健康检查（无需认证） |

### 运行时

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /v1/runtime/info | 运行时诊断（版本、配置、能力） |
| GET | /v1/runtime/tools | 工具诊断（已注册的工具提供者） |

### 线程

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /v1/threads | 列出所有线程 |
| POST | /v1/threads | 创建新线程 |
| GET | /v1/threads/:id | 获取线程详情 |
| PATCH | /v1/threads/:id | 更新线程元数据 |
| DELETE | /v1/threads/:id | 删除线程 |
| POST | /v1/threads/:id/fork | 克隆线程 |

### 目标 & 待办

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /v1/threads/:id/goal | 获取线程目标 |
| POST | /v1/threads/:id/goal | 设置/更新线程目标 |
| DELETE | /v1/threads/:id/goal | 清除线程目标 |
| GET | /v1/threads/:id/todos | 获取线程待办列表 |
| POST | /v1/threads/:id/todos | 设置线程待办列表 |
| DELETE | /v1/threads/:id/todos | 清除线程待办列表 |

### 轮次

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /v1/threads/:id/turns | 开始新轮次（触发 Agent 循环） |
| GET | /v1/threads/:id/turns/:turnId | 获取轮次详情 |
| POST | /v1/threads/:id/turns/:turnId/steer | 注入引导消息 |
| POST | /v1/threads/:id/turns/:turnId/interrupt | 中断运行中的轮次 |
| POST | /v1/threads/:id/compact | 手动触发上下文压缩 |

### 事件（SSE）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /v1/threads/:id/events | Server-Sent Events 流 |

实时推送事件类型：assistant_text_delta、assistant_reasoning_delta、tool_call_ready、tool_result、usage、pipeline_stage、error。

### 代码审查

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /v1/threads/:id/review | 启动代码审查 |

### 附件

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /v1/attachments | 上传附件 |
| GET | /v1/attachments/diagnostics | 附件存储诊断 |
| GET | /v1/attachments/:id | 获取附件元数据 |
| GET | /v1/attachments/:id/content | 获取附件内容 |

### 记忆

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /v1/memory | 列出记忆 |
| POST | /v1/memory | 创建记忆 |
| GET | /v1/memory/diagnostics | 记忆存储诊断 |
| PATCH | /v1/memory/:id | 更新记忆 |
| DELETE | /v1/memory/:id | 删除记忆 |

### 工作区

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /v1/workspace/status | 获取工作区状态（Git 信息等） |

### 用量

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /v1/usage | 获取用量统计 |

### 审批 & 用户输入

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /v1/approvals/:id | 处理待审批请求 |
| POST | /v1/user-input/:id | 处理待处理的用户输入 |

### 会话

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /v1/sessions/:id/resume-thread | 恢复会话 |

---

## 核心组件

### Agent 循环管道

AgentLoop 编排 11 个顺序执行的管道阶段：

1. **Setup** - 验证中止信号、初始化风暴断路器、启动目标计时器
2. **Steering Drain** - 将待处理的引导消息注入为用户输入
3. **History Loader** - 从会话存储加载并修复对话历史
4. **Model Router** - 解析使用的模型（固定或自动路由）
5. **Context Builder** - 收集技能、记忆、目标和指令
6. **Tool Catalog Manager** - 生成工具指纹并检测目录漂移
7. **Request Builder** - 组装模型请求并应用 Token 经济优化
8. **Response Handler** - 处理流式模型响应（文本、推理、工具调用）
9. **Tool Dispatcher** - 执行工具调用，支持只读工具并行优化和风暴断路器
10. **Budget Gate** - 执行成本预算限制及告警
11. **Goal Manager** - 记录目标已用时间

### 工具系统

工具通过提供者注册到 CapabilityRegistry：

| 提供者 | 类型 | 示例 |
|--------|------|------|
| 内置工具 | built-in | read, write, edit, grep, find, ls, bash, truncate |
| MCP | mcp | 任何 MCP 兼容服务器工具 |
| 网页 | web | web_fetch, web_search |
| 记忆 | memory | memory_store |
| 目标 | gui | get_goal, update_goal |
| 待办 | gui | todo_list, todo_write |
| 委托 | delegation | delegate_task |

### 存储

提供两种后端：

- **hybrid**（默认）- 磁盘 JSON 文件 + SQLite 索引，支持高效列表查询
- **file** - 纯 JSON 文件存储

---

## 测试

```bash
# 运行全部测试
bundle exec rspec

# 指定随机种子
bundle exec rspec --seed 42

# 运行特定文件
bundle exec rspec spec/loop/
bundle exec rspec spec/services/
```

2047 个用例，0 失败，15 个待定。

---

## 开发规范

### 代码布局约定

- domain/ - 纯 Ruby，不 require_relative 依赖其他模块
- ports/ - 抽象基类，方法抛出 NotImplementedError
- adapters/ - 继承端口的具体实现
- 每个文件单一职责
- 通过 index.rb 中的 autoload 声明实现延迟加载

### 添加新工具

1. 在 adapters/tool/ 中定义工具处理器
2. 在 server/runtime.rb 中注册到 CapabilityRegistry
3. 在提供者配置中定义其 Schema

---

## 许可证

MIT License。详见 LICENSE。
