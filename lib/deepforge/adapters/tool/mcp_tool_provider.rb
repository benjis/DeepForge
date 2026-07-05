# frozen_string_literal: true

# 文件用途：MCP（Model Context Protocol）工具提供者
# 使用方法：通过 build 方法连接 MCP 服务器并创建工具提供者

require 'digest'
require 'net/http'
require 'json'
require 'uri'
require 'open3'
require 'yaml'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：MCP 工具提供者，负责连接 MCP 服务器并管理远程工具
      module McpToolProvider
        # MCP 工具描述符结构体
        McpToolDescriptor = Struct.new(
          :name, :title, :description, :input_schema, :output_schema,
          :annotations, :execution, :icons, :_meta,
          keyword_init: true
        )

        # MCP 客户端接口结构体
        McpClientLike = Struct.new(:list_tools, :call_tool, :close, keyword_init: true)

        # MCP 服务器诊断信息结构体
        McpServerDiagnostic = Struct.new(
          :id, :enabled, :transport, :trust_scope, :available,
          :status, :tool_count, :catalog_fingerprint, :catalog_drift,
          :last_connected_at, :last_error,
          keyword_init: true
        )

        # MCP 工具提供者构建结果结构体
        McpToolProviderBuildResult = Struct.new(
          :providers, :diagnostics, :search, :connected_servers,
          :tool_count, :close,
          keyword_init: true
        )

        # MCP 工具提供者选项结构体
        McpToolProviderOptions = Struct.new(:client_factory, :now_iso, keyword_init: true)

        # MCP 连接状态结构体
        McpConnectionState = Struct.new(
          :server_id, :server, :client, :client_factory, :now_iso,
          :catalog_fingerprint, :catalog_drift, :last_connected_at, :last_error,
          keyword_init: true
        )

        # 方法功能：构建 MCP 工具提供者
        # 参数：config - MCP 配置，options - 选项（可选）
        # 返回值：McpToolProviderBuildResult 结构体
        def self.build(config, options = {})
          options ||= McpToolProviderOptions.new
          providers = []
          diagnostics = []
          connected = []
          catalog_records = []

          now_iso = options.now_iso || -> { Time.now.utc.strftime('%FT%TZ') }
          client_factory = options.client_factory || method(:create_sdk_mcp_client)

          unless config&.dig(:enabled)
            return McpToolProviderBuildResult.new(
              providers: [],
              diagnostics: [],
              search: nil,
              connected_servers: 0,
              tool_count: 0,
              close: -> {}
            )
          end

          (config[:servers] || {}).each do |server_id, server|
            unless server[:enabled]
              diagnostics << server_diagnostic({ server_id: server_id, server: server }, 'disabled', 0)
              next
            end

            begin
              client = client_factory.call(server_id, server)
              state = McpConnectionState.new(
                server_id: server_id,
                server: server,
                client: client,
                client_factory: client_factory,
                now_iso: now_iso,
                last_connected_at: now_iso.call
              )
              connected << state

              listed = refresh_mcp_connection_catalog(state)
              catalog_records.concat(listed.map { |tool| create_mcp_search_catalog_record(state, tool) })
              tools = listed.map { |tool| create_mcp_local_tool(state, tool) }

              providers << {
                id: "mcp:#{server_id}",
                kind: 'mcp',
                enabled: true,
                available: true,
                tools: tools
              }

              diagnostics << server_diagnostic(state, 'connected', tools.length)
            rescue StandardError => e
              diagnostics << server_diagnostic({ server_id: server_id, server: server }, 'error', 0, e.message)
            end
          end

          connected_servers = diagnostics.count { |d| d.status == 'connected' }
          tool_count = catalog_records.length

          McpToolProviderBuildResult.new(
            providers: providers,
            diagnostics: diagnostics,
            search: nil,
            connected_servers: connected_servers,
            tool_count: tool_count,
            close: lambda {
              connected.each do |s|
                s.client.close
              rescue StandardError
                nil
              end
            }
          )
        end

        # 方法功能：规范化 MCP 工具名称
        # 参数：server_id - 服务器 ID，tool_name - 工具名称
        # 返回值：规范化后的工具名称字符串
        def self.normalize_mcp_tool_name(server_id, tool_name)
          "mcp_#{slug(server_id)}_#{slug(tool_name)}"
        end

        # 方法功能：检查 MCP 服务器是否受信任
        # 参数：server - 服务器配置，workspace - 工作区路径
        # 返回值：布尔值
        def self.mcp_server_trusted?(server, workspace)
          return true if server[:trust_scope] == 'user'

          normalized_workspace = normalize_path_for_trust(workspace)
          (server[:trusted_workspace_roots] || []).any? do |root|
            normalized_root = normalize_path_for_trust(root)
            normalized_workspace == normalized_root || normalized_workspace.start_with?("#{normalized_root}/")
          end
        end

        # 方法功能：创建 SDK MCP 客户端
        # 参数：server_id - 服务器 ID，server - 服务器配置
        # 返回值：McpClientLike 结构体实例
        def self.create_sdk_mcp_client(_server_id, server)
          McpClientLike.new(
            list_tools: ->(options = nil) { list_all_mcp_tools(server, options) },
            call_tool: ->(input, options = nil) { call_mcp_tool(server, input, options) },
            close: -> { true }
          )
        end

        # 方法功能：列出所有 MCP 工具
        # 参数：server - 服务器配置，_options - 选项（未使用）
        # 返回值：包含工具列表的哈希
        def self.list_all_mcp_tools(server, _options = nil)
          tools = []

          if server[:transport] == 'stdio' && server[:command]
            cmd = [server[:command]] + (server[:args] || [])
            env = server[:env] || {}

            stdout, _stderr, status = Open3.capture3(env, *cmd)
            return { tools: tools } unless status.success?

            begin
              result = JSON.parse(stdout)
              tools = (result['tools'] || []).map { |t| parse_tool_descriptor(t) }
            rescue JSON::ParserError
              # Ignore parse errors
            end
          elsif server[:url]
            uri = URI(server[:url])
            headers = server[:headers] || {}

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'

            request = Net::HTTP::Post.new(uri.path.empty? ? '/' : uri.path)
            headers.each { |k, v| request[k] = v }
            request['Content-Type'] = 'application/json'
            request.body = JSON.generate({ jsonrpc: '2.0', id: 1, method: 'tools/list' })

            response = http.request(request)
            if response.code.to_i == 200
              result = JSON.parse(response.body)
              tools = (result.dig('result', 'tools') || []).map { |t| parse_tool_descriptor(t) }
            end
          end

          { tools: tools }
        end

        # 方法功能：调用 MCP 工具
        # 参数：server - 服务器配置，input - 输入参数，_options - 选项（未使用）
        # 返回值：工具调用结果或错误哈希
        def self.call_mcp_tool(server, input, _options = nil)
          if server[:transport] == 'stdio' && server[:command]
            cmd = [server[:command]] + (server[:args] || [])
            env = server[:env] || {}

            request_payload = JSON.generate({
                                              jsonrpc: '2.0',
                                              id: 1,
                                              method: 'tools/call',
                                              params: { name: input[:name], arguments: input[:arguments] || {} }
                                            })

            stdout, _stderr, status = Open3.capture3(env, *cmd, stdin_data: request_payload)
            return { error: 'command failed' } unless status.success?

            begin
              result = JSON.parse(stdout)
              result['result'] || result
            rescue JSON::ParserError
              { error: 'failed to parse response' }
            end
          elsif server[:url]
            uri = URI(server[:url])
            headers = server[:headers] || {}

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'

            request = Net::HTTP::Post.new(uri.path.empty? ? '/' : uri.path)
            headers.each { |k, v| request[k] = v }
            request['Content-Type'] = 'application/json'
            request.body = JSON.generate({
                                           jsonrpc: '2.0',
                                           id: 1,
                                           method: 'tools/call',
                                           params: { name: input[:name], arguments: input[:arguments] || {} }
                                         })

            response = http.request(request)
            if response.code.to_i == 200
              result = JSON.parse(response.body)
              result['result'] || result
            else
              { error: "HTTP #{response.code}" }
            end
          else
            { error: 'unsupported transport' }
          end
        end

        # 方法功能：解析工具描述符数据
        # 参数：data - 原始数据哈希
        # 返回值：McpToolDescriptor 结构体实例
        def self.parse_tool_descriptor(data)
          McpToolDescriptor.new(
            name: data['name'],
            title: data['title'],
            description: data['description'],
            input_schema: data['inputSchema'],
            output_schema: data['outputSchema'],
            annotations: data['annotations'],
            execution: data['execution'],
            icons: data['icons'],
            _meta: data['_meta']
          )
        end

        # 方法功能：创建 MCP 本地工具
        # 参数：state - 连接状态，descriptor - 工具描述符
        # 返回值：工具定义哈希
        def self.create_mcp_local_tool(state, descriptor)
          {
            name: normalize_mcp_tool_name(state.server_id, descriptor.name),
            description: descriptor.description || "MCP tool #{descriptor.name} from #{state.server_id}",
            input_schema: descriptor.input_schema || { type: 'object' },
            policy: policy_from_annotations(descriptor.annotations),
            should_advertise: ->(context) { mcp_server_trusted?(state.server, context[:workspace]) },
            execute: lambda { |args, context|
              unless mcp_server_trusted?(state.server, context[:workspace])
                return error_output("MCP server #{state.server_id} is not trusted for this workspace")
              end

              begin
                result = state.client.call_tool.call({
                                                       name: descriptor.name,
                                                       arguments: args
                                                     })
                {
                  output: {
                    server_id: state.server_id,
                    tool_name: descriptor.name,
                    result: result
                  },
                  is_error: result.is_a?(Hash) && result[:is_error] == true
                }
              rescue StandardError => e
                error_output("MCP tool call failed: #{e.message}")
              end
            }
          }
        end

        # 方法功能：创建 MCP 搜索目录记录
        # 参数：state - 连接状态，descriptor - 工具描述符
        # 返回值：搜索目录记录哈希
        def self.create_mcp_search_catalog_record(state, descriptor)
          {
            tool_id: "#{state.server_id}/#{descriptor.name}",
            server_id: state.server_id,
            server: state.server,
            client: state.client,
            descriptor: descriptor,
            normalizedName: normalize_mcp_tool_name(state.server_id, descriptor.name),
            policy: policy_from_annotations(descriptor.annotations)
          }
        end

        # 方法功能：刷新 MCP 连接目录
        # 参数：state - 连接状态
        # 返回值：工具描述符数组
        def self.refresh_mcp_connection_catalog(state)
          listed = state.client.list_tools.call
          tools = listed[:tools] || []

          next_fingerprint = catalog_fingerprint(tools.map(&:name))
          state.catalog_drift = state.catalog_fingerprint && state.catalog_fingerprint != next_fingerprint
          state.catalog_fingerprint = next_fingerprint
          state.last_error = nil

          tools
        end

        # 方法功能：从注解中提取策略
        # 参数：annotation - 注解哈希
        # 返回值：策略字符串
        def self.policy_from_annotations(annotation)
          if annotation&.dig(:readOnlyHint) && !annotation&.dig(:openWorldHint) && !annotation&.dig(:destructiveHint)
            return 'auto'
          end
          return 'on-request' if annotation&.dig(:destructiveHint)
          return 'untrusted' if annotation&.dig(:openWorldHint)

          'on-request'
        end

        # 方法功能：生成服务器诊断信息
        # 参数：state - 连接状态，status - 状态，tool_count - 工具数量，last_error - 最后错误（可选）
        # 返回值：McpServerDiagnostic 结构体实例
        def self.server_diagnostic(state, status, tool_count, last_error = nil)
          McpServerDiagnostic.new(
            id: state[:server_id],
            enabled: state[:server][:enabled],
            transport: state[:server][:transport],
            trust_scope: state[:server][:trust_scope],
            available: status == 'connected',
            status: status,
            tool_count: tool_count,
            catalog_fingerprint: state[:catalog_fingerprint],
            catalog_drift: state[:catalog_drift],
            last_connected_at: state[:last_connected_at],
            last_error: last_error
          )
        end

        # 方法功能：计算目录指纹
        # 参数：values - 值数组
        # 返回值：指纹字符串
        def self.catalog_fingerprint(values)
          Digest::SHA256.hexdigest(values.sort.to_json)[0, 16]
        end

        # 方法功能：将值转换为 slug 格式
        # 参数：value - 原始值
        # 返回值：slug 字符串
        def self.slug(value)
          result = value.strip.downcase.gsub(/[^a-z0-9_]+/, '_').gsub(/^_+|_+$/, '')
          result.empty? ? 'tool' : result
        end

        # 方法功能：为信任检查标准化路径
        # 参数：value - 路径字符串
        # 返回值：标准化后的路径
        def self.normalize_path_for_trust(value)
          value.gsub('\\', '/').gsub(%r{/+$}, '')
        end

        # 方法功能：生成错误输出格式
        # 参数：message - 错误消息
        # 返回值：包含错误信息的哈希
        def self.error_output(message)
          {
            output: { error: message },
            is_error: true
          }
        end
      end
    end
  end
end
