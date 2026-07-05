# frozen_string_literal: true

# 文件用途：运行时工厂的辅助方法，从 runtime.rb 提取
# 使用方法：由 runtime.rb 引入使用

module DeepForge
  module Server
    module RuntimeHelpers
      # 创建持久化存储
      def self.create_persistent_stores(data_dir, storage = nil)
        storage ||= { backend: 'hybrid' }

        case storage[:backend]
        when 'hybrid'
          thread_store = DeepForge::Adapters::Hybrid::AgentThreadStore.new(data_dir: data_dir)
          session_store = DeepForge::Adapters::Hybrid::HybridSessionStore.new(
            data_dir: data_dir,
            index: thread_store
          )
          {
            thread_store: thread_store,
            session_store: session_store,
            shutdown: -> { thread_store.close }
          }
        else
          thread_store = DeepForge::Adapters::FileStore::AgentThreadStore.new(data_dir: data_dir)
          session_store = DeepForge::Adapters::FileStore::FileSessionStore.new(data_dir: data_dir)
          {
            thread_store: thread_store,
            session_store: session_store,
            shutdown: -> {}
          }
        end
      end

      # 获取 Token 经济配置
      def self.token_economy_config_for_options(options)
        base = options.token_economy || {}
        base.merge(enabled: options.token_economy_mode)
      end

      # 从持久化事件中初始化使用量续传数据
      def self.seed_usage_carryover(thread_store, session_store, usage_service)
        thread_summaries = thread_store.list
        thread_summaries.each do |thread|
          events = session_store.load_events_since(thread[:id], 0)
          latest_usage = events
                         .select { |e| e[:kind] == 'usage' }
                         .max_by { |e| e[:seq] }

          usage_service.seed_thread(thread[:id], latest_usage[:usage]) if latest_usage
        end
      end

      # 构建不可变前缀
      def self.create_immutable_prefix(system_prompt:, pinned_constraints:)
        { system_prompt: system_prompt, pinned_constraints: pinned_constraints }
      end

      # 获取模型上下文配置文件
      def self.model_context_profiles_from_config(context_compaction: nil, models: nil)
        {}
      end

      # 获取模型能力配置
      def self.model_capabilities_for_model(model, _profiles)
        { model: model }
      end

      # 构建 MCP 工具提供者
      def self.build_mcp_tool_providers(_config)
        { providers: [], connected_servers: 0, tool_count: 0, diagnostics: [],
          search: { active: false, indexed_tool_count: 0, advertised_tool_count: 0 }, close: nil }
      end

      # 构建 Web 工具提供者
      def self.build_web_tool_providers(_config)
        { providers: [], fetch_available: false, search_available: false, provider: nil, diagnostics: [] }
      end

      # 构建记忆工具提供者
      def self.build_memory_tool_providers(_store)
        []
      end

      # 构建目标本地工具
      def self.build_goal_local_tools(_thread_service)
        []
      end

      # 构建待办事项本地工具
      def self.build_todo_local_tools(_thread_service)
        []
      end

      # 构建委托工具提供者
      def self.build_delegation_tool_providers(_runtime)
        []
      end

      # 构建默认本地工具
      def self.build_default_local_tools
        []
      end

      # 构建运行时能力清单
      def self.build_runtime_capability_manifest(**options)
        DeepForge::Contracts.build_runtime_capability_manifest(options)
      end

      # 创建子代理执行器
      def self.create_child_agent_executor(**_options)
        ->(_input) { 'completed' }
      end
    end
  end
end
