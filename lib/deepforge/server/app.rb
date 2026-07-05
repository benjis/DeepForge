# frozen_string_literal: true

#
# 文件用途：DeepForge Agent 的 HTTP/SSE Web 应用主文件
# 功能说明：基于 Roda 框架定义所有 API 路由，包括线程管理、对话轮次、附件上传、记忆存储、工作区状态、使用量统计等
# 使用方法：由 serve 入口启动，监听指定端口对外提供 RESTful API 服务

require 'roda'
require 'json'
require_relative 'middleware/auth'
require_relative 'middleware/sse'
require_relative 'routes/threads'
require_relative 'routes/turns'
require_relative 'routes/review'
require_relative 'routes/events'
require_relative 'routes/approvals'
require_relative 'routes/user_inputs'
require_relative 'routes/sessions'
require_relative 'routes/usage'
require_relative 'routes/runtime_info'
require_relative 'routes/attachments'
require_relative 'routes/memory'
require_relative 'routes/health'
require_relative 'routes/workspace'

module DeepForge
  # Web 应用类，继承 Roda，注册 JSON、流式响应、中断等插件
  class App < Roda
    plugin :json
    plugin :streaming
    plugin :halt

    # 主路由定义，所有请求从这里分发
    route do |r|
      # Get runtime from env (passed by the server)
      @runtime = r.env['deepforge.runtime']

      # Health check (unauthenticated)
      r.on 'health' do
        r.get do
          { 'status' => 'ok', 'service' => 'deepforge', 'mode' => 'serve' }
        end
      end

      # All /v1 routes require auth
      r.on 'v1' do
        r.on 'runtime' do
          r.on 'info' do
            r.get do
              authorize_request!
              Routes::RuntimeInfo.runtime_info_json_response(@runtime)
            end
          end

          r.on 'tools' do
            r.get do
              authorize_request!
              Routes::RuntimeInfo.runtime_tool_diagnostics_json_response(@runtime)
            end
          end
        end

        r.on 'threads' do
          r.get do
            authorize_request!
            Routes::Threads.list_threads(@runtime[:thread_service], request_env)
          end

          r.post do
            authorize_request!
            Routes::Threads.create_thread(@runtime[:thread_service], request_env)
          end

          r.on String do |thread_id|
            r.get do
              authorize_request!
              Routes::Threads.get_thread(@runtime[:thread_service], thread_id, @runtime[:session_store])
            end

            r.on(method: :patch) do
              authorize_request!
              Routes::Threads.update_thread(@runtime[:thread_service], thread_id, request_env)
            end

            r.on(method: :delete) do
              authorize_request!
              Routes::Threads.delete_thread(@runtime[:thread_service], thread_id)
            end

            r.on 'fork' do
              r.post do
                authorize_request!
                Routes::Threads.fork_thread(@runtime[:thread_service], thread_id, request_env)
              end
            end

            r.on 'goal' do
              r.get do
                authorize_request!
                Routes::Threads.get_thread_goal(@runtime[:thread_service], thread_id)
              end

              r.post do
                authorize_request!
                Routes::Threads.set_thread_goal(@runtime[:thread_service], thread_id, request_env)
              end

              r.on(method: :delete) do
                authorize_request!
                Routes::Threads.clear_thread_goal(@runtime[:thread_service], thread_id)
              end
            end

            r.on 'todos' do
              r.get do
                authorize_request!
                Routes::Threads.get_thread_todos(@runtime[:thread_service], thread_id)
              end

              r.post do
                authorize_request!
                Routes::Threads.set_thread_todos(@runtime[:thread_service], thread_id, request_env)
              end

              r.on(method: :delete) do
                authorize_request!
                Routes::Threads.clear_thread_todos(@runtime[:thread_service], thread_id)
              end
            end

            r.on 'turns' do
              r.post do
                authorize_request!
                Routes::Turns.start_turn(@runtime[:turn_service], thread_id, request_env) do |response|
                  @runtime[:run_turn]&.call(response[:thread_id], response[:turn_id])
                end
              end

              r.on String do |turn_id|
                r.get do
                  authorize_request!
                  Routes::Turns.get_turn(@runtime[:turn_service], thread_id, turn_id)
                end

                r.on 'steer' do
                  r.post do
                    authorize_request!
                    Routes::Turns.steer_turn(@runtime[:turn_service], thread_id, turn_id, request_env)
                  end
                end

                r.on 'interrupt' do
                  r.post do
                    authorize_request!
                    Routes::Turns.interrupt_turn(@runtime[:turn_service], thread_id, turn_id, request_env)
                  end
                end
              end
            end

            r.on 'compact' do
              r.post do
                authorize_request!
                Routes::Turns.compact_turn(@runtime[:turn_service], thread_id, request_env)
              end
            end

            r.on 'review' do
              r.post do
                authorize_request!
                unless @runtime[:review_service] && @runtime[:run_review]
                  halt 503, { 'error' => 'review is not available' }
                end
                Routes::Review.start_review(@runtime, thread_id, request_env)
              end
            end

            r.on 'events' do
              r.get do
                authorize_request!
                stream_sse(thread_id)
              end
            end
          end
        end

        r.on 'attachments' do
          r.post do
            authorize_request!
            Routes::Attachments.upload_attachment(@runtime[:attachment_store], request_env)
          end

          r.get 'diagnostics' do
            authorize_request!
            Routes::Attachments.attachment_diagnostics(@runtime[:attachment_store])
          end

          r.on String do |id|
            r.get 'content' do
              authorize_request!
              Routes::Attachments.get_attachment_content(@runtime[:attachment_store], id)
            end

            r.get do
              authorize_request!
              Routes::Attachments.get_attachment_metadata(@runtime[:attachment_store], id)
            end
          end
        end

        r.on 'memory' do
          r.get do
            authorize_request!
            Routes::Memory.list_memories(@runtime[:memory_store], request_env)
          end

          r.post do
            authorize_request!
            Routes::Memory.create_memory(@runtime[:memory_store], request_env)
          end

          r.get 'diagnostics' do
            authorize_request!
            Routes::Memory.memory_diagnostics(@runtime[:memory_store])
          end

          r.on String do |id|
            r.on(method: :patch) do
              authorize_request!
              Routes::Memory.update_memory(@runtime[:memory_store], id, request_env)
            end

            r.on(method: :delete) do
              authorize_request!
              Routes::Memory.delete_memory(@runtime[:memory_store], id)
            end
          end
        end

        r.on 'workspace' do
          r.get 'status' do
            authorize_request!
            Routes::Workspace.build_workspace_status_response(
              inspector: @runtime[:workspace_inspector],
              path: r.params['path']
            )
          end
        end

        r.on 'usage' do
          r.get do
            authorize_request!
            Routes::Usage.usage_json_response(@runtime)
          end
        end

        r.on 'approvals' do
          r.on String do |id|
            r.post do
              authorize_request!
              Routes::Approvals.decide_approval(
                approvalId: id,
                request_env: request_env,
                gate: @runtime[:approval_gate],
                events: @runtime[:events]
              )
            end
          end
        end

        r.on 'user-input' do
          r.on String do |id|
            r.post do
              authorize_request!
              Routes::UserInputs.resolve_user_input(
                id: id,
                request_env: request_env,
                gate: @runtime[:user_input_gate],
                events: @runtime[:events]
              )
            end
          end
        end

        r.on 'sessions' do
          r.on String do |id|
            r.post 'resume-thread' do
              authorize_request!
              Routes::Sessions.resume_session(@runtime[:thread_service], id, request_env)
            end
          end
        end
      end
    end

    private

    # 方法功能：校验请求的 Bearer Token 是否合法
    # 使用方法：在需要认证的路由中调用，若 token 无效或缺失则返回 401
    def authorize_request!
      return if @runtime[:insecure]

      token = DeepForge::Server.bearer_token(request_env[:headers])
      return if token && token == @runtime[:runtime_token]

      halt 401, { 'code' => 'unauthorized', 'message' => 'invalid or missing token' }
    end

    # 方法功能：从当前请求中提取标准化的请求环境信息
    # 返回值：Hash，包含 method、path、body、headers、url
    def request_env
      body = request.body.respond_to?(:read) ? request.body.read : request.body.to_s
      {
        method: request.request_method,
        path: request.path,
        body: body,
        headers: extract_headers,
        url: request.url
      }
    end

    # 方法功能：从 Rack 环境中提取 HTTP 头信息，转换为小写连字符格式
    # 返回值：Hash，键为 header 名称，值为 header 值
    def extract_headers
      headers = {}
      request.env.each do |key, value|
        if key.start_with?('HTTP_')
          header_name = key.sub('HTTP_', '').downcase.gsub('_', '-')
          headers[header_name] = value
        end
      end
      headers['content-type'] = request.env['CONTENT_TYPE'] if request.env['CONTENT_TYPE']
      headers
    end

    # 方法功能：通过 SSE（Server-Sent Events）流式推送线程事件给客户端
    # 参数：thread_id - 线程 ID，用于订阅该线程的事件流
    def stream_sse(thread_id)
      response['Content-Type'] = 'text/event-stream; charset=utf-8'
      response['Cache-Control'] = 'no-cache, no-transform'
      response['Connection'] = 'keep-alive'

      stream do |out|
        Routes::Events.stream_events(
          thread_id: thread_id,
          event_bus: @runtime[:event_bus],
          session_store: @runtime[:session_store],
          allocate_seq: @runtime[:allocate_seq],
          output: out
        )
      end
    end
  end
end
