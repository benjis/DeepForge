# frozen_string_literal: true

# 文件用途：Web 工具提供者
# 使用方法：通过 build 方法创建 Web 抓取和搜索工具

require 'net/http'
require 'uri'
require 'json'
require 'time'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供 Web 抓取和搜索工具
      module WebToolProvider
        # 默认 Web 请求超时时间（毫秒）
        DEFAULT_WEB_TIMEOUT_MS = 15_000
        # 默认最大抓取字节数
        DEFAULT_WEB_MAX_BYTES = 1_000_000
        # 默认搜索结果数量
        DEFAULT_SEARCH_LIMIT = 5
        # 最大搜索结果数量
        MAX_SEARCH_LIMIT = 10

        # Web 提供者诊断信息结构体
        WebProviderDiagnostic = Struct.new(
          :id, :enabled, :available, :fetch_available,
          :search_available, :provider, :reason,
          keyword_init: true
        )

        # Web 工具提供者构建结果结构体
        WebToolProviderBuildResult = Struct.new(
          :providers, :diagnostics, :fetch_available,
          :search_available, :provider,
          keyword_init: true
        )

        # Web 工具提供者选项结构体
        WebToolProviderOptions = Struct.new(:provider, :now_iso, keyword_init: true)

        # 方法功能：构建 Web 工具提供者
        # 参数：config - Web 配置，options - 选项（可选）
        # 返回值：WebToolProviderBuildResult 结构体
        def self.build(config, options = {})
          options ||= WebToolProviderOptions.new

          unless config&.dig(:enabled)
            return WebToolProviderBuildResult.new(
              providers: [],
              diagnostics: [],
              fetch_available: false,
              search_available: false
            )
          end

          provider = options.provider || (config[:fetch_enabled] ? FetchWebProvider.new(options.now_iso) : UnavailableWebProvider.new(config[:provider]))

          tools = []
          tools << create_fetch_tool(config, provider) if config[:fetch_enabled]
          tools << create_search_tool(config, provider) if config[:search_enabled]

          fetch_available = config[:fetch_enabled] && provider.respond_to?(:fetch)
          search_available = config[:search_enabled] && provider.respond_to?(:search)

          reason = if tools.empty?
                     'web tools are disabled by config'
                   elsif !fetch_available && !search_available
                     'web provider is unavailable'
                   end

          WebToolProviderBuildResult.new(
            providers: if tools.length.positive?
                         [{
                           id: 'web',
                           kind: 'web',
                           enabled: true,
                           available: true,
                           **(reason ? { reason: reason } : {}),
                           tools: tools
                         }]
                       else
                         []
                       end,
            diagnostics: [WebProviderDiagnostic.new(
              id: 'web',
              enabled: true,
              available: fetch_available || search_available,
              fetch_available: fetch_available,
              search_available: search_available,
              provider: provider.id,
              reason: reason
            )],
            fetch_available: fetch_available,
            search_available: search_available,
            provider: provider.id
          )
        end

        # 方法功能：创建 Web 抓取工具
        # 参数：config - 配置，provider - Web 提供者
        # 返回值：工具定义哈希
        def self.create_fetch_tool(config, provider)
          {
            name: 'web_fetch',
            description: 'Fetch an allowed HTTP or HTTPS URL and return extracted text with source metadata.',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string' },
                max_bytes: { type: 'number' },
                timeout_ms: { type: 'number' }
              },
              required: ['url'],
              additional_properties: false
            },
            policy: 'untrusted',
            execute: lambda { |args, context|
              started_at = Time.now.to_i * 1000
              raw_url = pick_string(args[:url])
              return tool_error('invalid_url', 'url is required') unless raw_url

              policy_result = validate_url_policy(raw_url, config)
              unless policy_result[:ok]
                return tool_error('policy_blocked', policy_result[:reason],
                                  telemetry(started_at: started_at, policy: 'blocked', url: raw_url))
              end

              unless provider.respond_to?(:fetch)
                return tool_error('provider_unavailable',
                                  'web fetch provider is unavailable')
              end

              max_bytes = bounded_int(args[:max_bytes], DEFAULT_WEB_MAX_BYTES, 1, DEFAULT_WEB_MAX_BYTES)
              timeout_ms = bounded_int(args[:timeout_ms], DEFAULT_WEB_TIMEOUT_MS, 1, DEFAULT_WEB_TIMEOUT_MS)

              begin
                result = provider.fetch(
                  url: policy_result[:url],
                  max_bytes: max_bytes,
                  timeout_ms: timeout_ms,
                  signal: context[:abort_signal]
                )
                {
                  output: fetch_output(result, telemetry(
                                                 started_at: started_at,
                                                 policy: 'allowed',
                                                 url: policy_result[:url],
                                                 provider: provider.id,
                                                 byte_count: result[:byte_count]
                                               ))
                }
              rescue StandardError => e
                tool_error('fetch_failed', e.message, telemetry(
                                                        started_at: started_at,
                                                        policy: 'allowed',
                                                        url: policy_result[:url],
                                                        provider: provider.id
                                                      ))
              end
            }
          }
        end

        # 方法功能：创建 Web 搜索工具
        # 参数：config - 配置，provider - Web 提供者
        # 返回值：工具定义哈希
        def self.create_search_tool(_config, provider)
          {
            name: 'web_search',
            description: 'Search the web through the configured provider and return ranked results with source metadata.',
            input_schema: {
              type: 'object',
              properties: {
                query: { type: 'string' },
                limit: { type: 'number' },
                timeout_ms: { type: 'number' }
              },
              required: ['query'],
              additional_properties: false
            },
            policy: 'untrusted',
            execute: lambda { |args, context|
              started_at = Time.now.to_i * 1000
              query = pick_string(args[:query])
              return tool_error('invalid_query', 'query is required') unless query

              unless provider.respond_to?(:search)
                return tool_error('provider_unavailable',
                                  'web search provider is unavailable')
              end

              limit = bounded_int(args[:limit], DEFAULT_SEARCH_LIMIT, 1, MAX_SEARCH_LIMIT)
              timeout_ms = bounded_int(args[:timeout_ms], DEFAULT_WEB_TIMEOUT_MS, 1, DEFAULT_WEB_TIMEOUT_MS)

              begin
                results = provider.search(
                  query: query,
                  limit: limit,
                  timeout_ms: timeout_ms,
                  signal: context[:abort_signal]
                )
                {
                  output: search_output(query, provider.id, results, telemetry(
                                                                       started_at: started_at,
                                                                       policy: 'allowed',
                                                                       provider: provider.id,
                                                                       query: query,
                                                                       result_count: results.length
                                                                     ))
                }
              rescue StandardError => e
                tool_error('search_failed', e.message, telemetry(
                                                         started_at: started_at,
                                                         policy: 'allowed',
                                                         provider: provider.id,
                                                         query: query
                                                       ))
              end
            }
          }
        end

        # 方法功能：验证 URL 策略
        # 参数：raw_url - 原始 URL，config - 配置
        # 返回值：包含 :ok 和可选 :url 或 :reason 的哈希
        def self.validate_url_policy(raw_url, config)
          begin
            url = URI.parse(raw_url)
          rescue URI::InvalidURIError
            return { ok: false, reason: 'URL must be absolute' }
          end

          unless %w[http https].include?(url.scheme)
            return { ok: false, reason: 'only http and https URLs are allowed' }
          end

          hostname = url.host.to_s.downcase

          deny_domains = config[:deny_domains] || []
          allow_domains = config[:allow_domains] || []

          if deny_domains.any? { |domain| domain_matches?(hostname, domain) }
            return { ok: false, reason: "domain is denied: #{hostname}" }
          end

          if allow_domains.length.positive? && allow_domains.none? { |domain| domain_matches?(hostname, domain) }
            return { ok: false, reason: "domain is not allowed: #{hostname}" }
          end

          { ok: true, url: url }
        end

        # 方法功能：检查域名是否匹配
        # 参数：hostname - 主机名，domain - 域名
        # 返回值：布尔值
        def self.domain_matches?(hostname, domain)
          normalized = domain.downcase.sub(/^\./, '')
          hostname == normalized || hostname.end_with?(".#{normalized}")
        end

        # 方法功能：格式化抓取结果输出
        # 参数：result - 抓取结果，tool_telemetry - 遥测信息
        # 返回值：格式化后的输出哈希
        def self.fetch_output(result, tool_telemetry)
          source = {
            source_id: result[:source_id],
            url: result[:final_url],
            title: result[:title],
            retrieved_at: result[:retrieved_at]
          }
          {
            source_id: result[:source_id],
            url: result[:url],
            final_url: result[:final_url],
            title: result[:title],
            retrieved_at: result[:retrieved_at],
            content_type: result[:content_type],
            text: result[:text],
            byte_count: result[:byte_count],
            truncated: result[:truncated],
            sources: [source],
            citations: [source],
            telemetry: tool_telemetry
          }
        end

        # 方法功能：格式化搜索结果输出
        # 参数：query - 查询字符串，provider - 提供者，results - 搜索结果，tool_telemetry - 遥测信息
        # 返回值：格式化后的输出哈希
        def self.search_output(query, provider, results, tool_telemetry)
          sources = results.map do |result|
            {
              source_id: result[:source_id],
              url: result[:url],
              title: result[:title],
              retrieved_at: result[:retrieved_at]
            }
          end
          {
            query: query,
            provider: provider,
            results: results,
            sources: sources,
            citations: sources,
            telemetry: tool_telemetry
          }
        end

        # 方法功能：从原始内容中提取可读文本
        # 参数：raw - 原始内容，content_type - 内容类型
        # 返回值：包含 :text 和可选 :title 的哈希
        def self.extract_readable_text(raw, content_type)
          return { text: normalize_whitespace(raw) } unless content_type.to_s.downcase.include?('html')

          title_match = raw.match(%r{<title[^>]*>([\s\S]*?)</title>}i)
          title = title_match[1] if title_match

          without_scripts = raw
                            .gsub(%r{<script[\s\S]*?</script>}i, ' ')
                            .gsub(%r{<style[\s\S]*?</style>}i, ' ')

          text = without_scripts
                 .gsub(%r{<br\s*/?>}i, "\n")
                 .gsub(%r{</(p|div|li|h[1-6])>}i, "\n")
                 .gsub(/<[^>]+>/, ' ')

          result = { text: normalize_whitespace(decode_html_entities(text)) }
          result[:title] = normalize_whitespace(decode_html_entities(title)) if title
          result
        end

        # 方法功能：解码 HTML 实体
        # 参数：value - 包含 HTML 实体的字符串
        # 返回值：解码后的字符串
        def self.decode_html_entities(value)
          value
            .gsub('&nbsp;', ' ')
            .gsub('&amp;', '&')
            .gsub('&lt;', '<')
            .gsub('&gt;', '>')
            .gsub('&quot;', '"')
            .gsub('&#39;', "'")
        end

        # 方法功能：标准化空白字符
        # 参数：value - 字符串
        # 返回值：标准化后的字符串
        def self.normalize_whitespace(value)
          value.gsub("\r", '').gsub(/[ \t]+/, ' ').gsub(/\n{3,}/, "\n\n").strip
        end

        # 方法功能：生成遥测信息
        # 参数：started_at - 开始时间，policy - 策略，provider - 提供者，url - URL，query - 查询，byte_count - 字节数，result_count - 结果数
        # 返回值：遥测信息哈希
        def self.telemetry(started_at:, policy:, provider: nil, url: nil, query: nil, byte_count: nil,
                           result_count: nil)
          {
            provider: provider,
            url: url,
            query: query,
            byte_count: byte_count,
            result_count: result_count,
            duration_ms: (Time.now.to_i * 1000) - started_at,
            cache_status: 'miss',
            policy: policy
          }
        end

        # 方法功能：生成工具错误输出
        # 参数：code - 错误代码，message - 错误消息，tool_telemetry - 遥测信息（可选）
        # 返回值：错误输出哈希
        def self.tool_error(code, message, tool_telemetry = nil)
          result = {
            output: {
              error: { code: code, message: message }
            },
            is_error: true
          }
          result[:output][:telemetry] = tool_telemetry if tool_telemetry
          result
        end

        # 方法功能：获取字符串值
        # 参数：value - 输入值
        # 返回值：字符串或 nil
        def self.pick_string(value)
          value.is_a?(String) && !value.strip.empty? ? value.strip : nil
        end

        # 方法功能：将值限制在整数范围内
        # 参数：value - 输入值，fallback - 备用值，min - 最小值，max - 最大值
        # 返回值：限制后的整数
        def self.bounded_int(value, fallback, min, max)
          return fallback unless value.is_a?(Numeric) && value.finite?

          [[value.to_i, min].max, max].min
        end

        # 类功能：基于 HTTP 的 Web 抓取提供者实现
        class FetchWebProvider
          attr_reader :id

          # 方法功能：初始化 Web 抓取提供者
          # 参数：now_iso - 获取当前时间的函数（可选）
          def initialize(now_iso = nil)
            @id = 'fetch'
            @now_iso = now_iso || -> { Time.now.utc.strftime('%FT%TZ') }
          end

          # 方法功能：抓取 URL 内容
          # 参数：url - URL 字符串，max_bytes - 最大字节数，timeout_ms - 超时时间，signal - 中止信号（可选）
          # 返回值：抓取结果哈希
          def fetch(url:, max_bytes:, timeout_ms:, signal: nil)
            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.open_timeout = timeout_ms / 1000.0
            http.read_timeout = timeout_ms / 1000.0

            request = Net::HTTP::Get.new(uri)
            response = http.request(request)

            raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

            content_length = response['content-length']&.to_i
            raise "content exceeds #{max_bytes} byte limit" if content_length && content_length > max_bytes

            body = response.body
            raise "content exceeds #{max_bytes} byte limit" if body.bytesize > max_bytes

            content_type = response['content-type']
            extracted = extract_readable_text(body, content_type)
            final_url = response['uri']&.to_s || url

            {
              source_id: "fetch:#{Digest::SHA256.hexdigest(final_url)[0, 16]}",
              url: url,
              final_url: final_url,
              title: extracted[:title],
              content_type: content_type,
              text: extracted[:text],
              retrieved_at: @now_iso.call,
              byte_count: body.bytesize,
              truncated: false
            }
          end
        end

        # 类功能：不可用的 Web 提供者占位实现
        class UnavailableWebProvider
          attr_reader :id

          # 方法功能：初始化不可用的 Web 提供者
          # 参数：provider_name - 提供者名称（可选）
          def initialize(provider_name = nil)
            @id = provider_name || 'unavailable'
          end
        end
      end
    end
  end
end
