# frozen_string_literal: true

# 文件用途：MCP 工具搜索模块
# 使用方法：提供 mcp_search、mcp_describe、mcp_call 等工具用于搜索和调用 MCP 工具

module DeepForge
  module Adapters
    module Tool
      # 模块功能：MCP 工具搜索，基于自然语言意图搜索已连接的 MCP 工具
      module McpToolSearch
        # 搜索工具名称
        MCP_SEARCH_TOOL_NAME = 'mcp_search'
        # 描述工具名称
        MCP_DESCRIBE_TOOL_NAME = 'mcp_describe'
        # 调用工具名称
        MCP_CALL_TOOL_NAME = 'mcp_call'
        # 刷新目录工具名称
        MCP_REFRESH_CATALOG_TOOL_NAME = 'mcp_refresh_catalog'

        # 停用词列表，用于分词时过滤
        STOP_WORDS = %w[
          the and for with this that from into about there their will would could
          should have has are was were been not but you your our can then when what how
        ].freeze

        # 动作同义词映射，支持中英文
        ACTION_SYNONYMS = {
          'search' => %w[find lookup query 查 搜索 检索 找],
          'find' => %w[search lookup query 查找],
          'list' => %w[show enumerate 列出 列表],
          'get' => %w[read fetch retrieve describe 获取 读取 查看],
          'create' => %w[add new make 创建 新增],
          'update' => %w[edit modify set change 更新 修改],
          'delete' => %w[remove destroy 删除 移除],
          'send' => %w[post publish reply comment 发送 回复 评论]
        }.freeze

        # MCP 搜索目录记录结构体
        McpSearchCatalogRecord = Struct.new(
          :tool_id, :server_id, :server, :client, :descriptor,
          :normalizedName, :policy,
          keyword_init: true
        )

        # MCP 搜索目录状态结构体
        McpSearchCatalogState = Struct.new(
          :records, :last_refreshed_at, :last_error,
          :catalog_fingerprint, :catalog_drift,
          keyword_init: true
        )

        # MCP 搜索提供者选项结构体
        McpSearchProviderOptions = Struct.new(
          :config, :state, :refresh_catalog, :is_server_trusted,
          keyword_init: true
        )

        # 方法功能：创建 MCP 搜索提供者
        # 参数：options - 搜索提供者选项
        # 返回值：工具提供者哈希
        def self.create_provider(options)
          {
            id: 'mcp:search',
            kind: 'mcp',
            enabled: true,
            available: true,
            tools: create_mcp_search_tools(options)
          }
        end

        # 方法功能：创建所有 MCP 搜索工具
        # 参数：options - 搜索提供者选项
        # 返回值：工具定义数组
        def self.create_mcp_search_tools(options)
          [
            create_search_tool(options),
            create_describe_tool(options),
            create_call_tool(options),
            create_refresh_catalog_tool(options)
          ]
        end

        # 方法功能：创建 MCP 搜索工具
        # 参数：options - 搜索提供者选项
        # 返回值：工具定义哈希
        def self.create_search_tool(options)
          {
            name: MCP_SEARCH_TOOL_NAME,
            description: 'Search connected MCP tools by natural-language intent, server, action, and parameter names.',
            input_schema: {
              type: 'object',
              properties: {
                query: { type: 'string', description: 'The user intent or task to find MCP tools for.' },
                top_k: { type: 'number', description: 'Maximum number of matching tools to return.' },
                server_id: { type: 'string', description: 'Optional MCP server id to search within.' }
              },
              required: ['query']
            },
            policy: 'auto',
            execute: lambda { |args, context|
              query = string_arg(args[:query])
              return error_output('query is required') if query.empty?

              server_id = string_arg(args[:server_id])
              top_k = clamp_positive_int(number_arg(args[:top_k]), options.config[:top_k_default],
                                         options.config[:top_k_max])

              records = trusted_records(options, context)
                        .reject { |r| server_id && r.server_id != server_id }

              results = search_records(records, query, top_k, options.config)

              {
                output: {
                  query: query,
                  total_indexed: options.state.records.length,
                  searched_tools: records.length,
                  results: results.map { |r| format_search_result(r) }
                }
              }
            }
          }
        end

        # 方法功能：创建 MCP 描述工具
        # 参数：options - 搜索提供者选项
        # 返回值：工具定义哈希
        def self.create_describe_tool(options)
          {
            name: MCP_DESCRIBE_TOOL_NAME,
            description: 'Return the full schema and metadata for a connected MCP tool found by mcp_search.',
            input_schema: {
              type: 'object',
              properties: {
                tool_id: { type: 'string', description: 'Canonical MCP tool id in the form serverId/toolName.' }
              },
              required: ['tool_id']
            },
            policy: 'auto',
            execute: lambda { |args, context|
              tool_id = string_arg(args[:tool_id])
              record = resolve_trusted_record(options, context, tool_id)
              return error_output("unknown MCP tool: #{tool_id}") unless record

              { output: describe_record(record) }
            }
          }
        end

        # 方法功能：创建 MCP 调用工具
        # 参数：options - 搜索提供者选项
        # 返回值：工具定义哈希
        def self.create_call_tool(options)
          {
            name: MCP_CALL_TOOL_NAME,
            description: 'Call a connected MCP tool by canonical tool id with JSON arguments.',
            input_schema: {
              type: 'object',
              properties: {
                tool_id: { type: 'string', description: 'Canonical MCP tool id in the form serverId/toolName.' },
                arguments: { type: 'object', description: 'Arguments matching the MCP tool input schema.' }
              },
              required: %w[tool_id arguments]
            },
            policy: 'on-request',
            execute: lambda { |args, context|
              tool_id = string_arg(args[:tool_id])
              record = resolve_trusted_record(options, context, tool_id)
              return error_output("unknown MCP tool: #{tool_id}") unless record

              call_args = object_arg(args[:arguments])
              begin
                result = record.client.call_tool.call({
                                                        name: record.descriptor.name,
                                                        arguments: call_args
                                                      })
                {
                  output: {
                    server_id: record.server_id,
                    tool_name: record.descriptor.name,
                    tool_id: record.tool_id,
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

        # 方法功能：创建 MCP 刷新目录工具
        # 参数：options - 搜索提供者选项
        # 返回值：工具定义哈希
        def self.create_refresh_catalog_tool(options)
          {
            name: MCP_REFRESH_CATALOG_TOOL_NAME,
            description: 'Refresh the MCP tool catalog and rebuild the local search index.',
            input_schema: {
              type: 'object',
              properties: {}
            },
            policy: 'auto',
            execute: lambda { |_args, _context|
              begin
                records = options.refresh_catalog.call
                {
                  output: {
                    refreshed_at: options.state.last_refreshed_at,
                    total_indexed: records.length,
                    catalog_fingerprint: options.state.catalog_fingerprint,
                    catalog_drift: options.state.catalog_drift == true
                  }
                }
              rescue StandardError => e
                error_output("refresh failed: #{e.message}")
              end
            }
          }
        end

        # 方法功能：获取受信任的记录
        # 参数：options - 搜索提供者选项，context - 上下文
        # 返回值：受信任的记录数组
        def self.trusted_records(options, context)
          options.state.records.select do |record|
            options.is_server_trusted.call(record.server, context[:workspace])
          end
        end

        # 方法功能：解析受信任的记录
        # 参数：options - 搜索提供者选项，context - 上下文，tool_id - 工具 ID
        # 返回值：记录或 nil
        def self.resolve_trusted_record(options, context, tool_id)
          return nil if tool_id.empty?

          trusted_records(options, context).find { |r| r.tool_id == tool_id }
        end

        # 方法功能：搜索记录
        # 参数：records - 记录数组，query_text - 查询文本，top_k - 返回数量，config - 配置
        # 返回值：搜索结果数组
        def self.search_records(records, query_text, top_k, config)
          query = build_query(query_text)
          return [] if query[:terms].empty?

          index = build_index(records)

          index[:tools]
            .map do |tool|
              keyword = keyword_score(tool, query)
              {
                record: tool[:record],
                score: bm25_score(tool, index, query, config) + keyword[:score],
                keywords: keyword[:keywords]
              }
            end
            .filter { |r| r[:score] >= config[:min_score] && r[:keywords].length.positive? }
            .sort_by { |r| -r[:score] }
            .first(top_k)
        end

        # 方法功能：构建搜索索引
        # 参数：records - 记录数组
        # 返回值：索引哈希
        def self.build_index(records)
          tools = records.map { |r| index_record(r) }
          document_frequency = {}
          token_count = 0

          tools.each do |tool|
            token_count += tool[:tokens].length
            tool[:tokens].uniq.each do |token|
              document_frequency[token] = (document_frequency[token] || 0) + 1
            end
          end

          {
            tools: tools,
            document_frequency: document_frequency,
            average_length: tools.length.positive? ? token_count.to_f / tools.length : 1
          }
        end

        # 方法功能：索引单条记录
        # 参数：record - 记录
        # 返回值：索引记录哈希
        def self.index_record(record)
          descriptor = record.descriptor
          input_schema = descriptor.input_schema || { type: 'object' }
          param_text = extract_schema_text(input_schema)

          exact = [
            record.server_id,
            descriptor.name,
            descriptor.title,
            descriptor.annotations&.dig(:title),
            record.normalizedName,
            record.tool_id
          ].compact.join(' ')

          action = action_words(descriptor.name)
          semantic = [descriptor.description, descriptor.title, descriptor.annotations&.dig(:title)].compact.join(' ')

          risk = [
            descriptor.annotations&.dig(:readOnlyHint) ? 'read read-only readonly safe' : '',
            descriptor.annotations&.dig(:destructiveHint) ? 'delete destructive dangerous high-risk' : '',
            descriptor.annotations&.dig(:openWorldHint) ? 'external network open-world' : ''
          ].join(' ')

          server = [record.server_id, record.server[:transport], record.server[:trust_scope]].join(' ')

          exact_tokens = tokenize_mcp_search_text(exact)
          action_tokens = tokenize_mcp_search_text(action)
          param_tokens = tokenize_mcp_search_text(param_text)

          tokens = repeat_tokens(exact_tokens, 5) +
                   repeat_tokens(action_tokens, 3) +
                   repeat_tokens(param_tokens, 2) +
                   tokenize_mcp_search_text(semantic) +
                   tokenize_mcp_search_text(server) +
                   tokenize_mcp_search_text(risk)

          {
            record: record,
            tokens: tokens,
            term_frequency: term_frequency(tokens),
            exact_tokens: exact_tokens.to_set,
            action_tokens: action_tokens.to_set,
            param_tokens: param_tokens.to_set
          }
        end

        # 方法功能：构建查询
        # 参数：text - 查询文本
        # 返回值：查询哈希
        def self.build_query(text)
          weights = {}
          expand_query_tokens(tokenize_mcp_search_text(text)).each do |token|
            weights[token] = (weights[token] || 0) + 1
          end

          {
            text: text,
            terms: weights.keys.first(48),
            weights: weights
          }
        end

        # 方法功能：扩展查询令牌
        # 参数：tokens - 令牌数组
        # 返回值：扩展后的令牌数组
        def self.expand_query_tokens(tokens)
          out = tokens.dup
          tokens.each do |token|
            synonyms = ACTION_SYNONYMS[token]
            out.concat(synonyms) if synonyms
            ACTION_SYNONYMS.each do |action, values|
              out << action if values.include?(token)
            end
          end
          out
        end

        # 方法功能：计算 BM25 分数
        # 参数：tool - 工具索引，index - 搜索索引，query - 查询，config - 配置
        # 返回值：分数值
        def self.bm25_score(tool, index, query, config)
          total_docs = [index[:tools].length, 1].max
          average_length = [index[:average_length], 1].max
          k1 = config[:bm25][:k1]
          b = config[:bm25][:b]

          score = 0
          query[:terms].each do |term|
            tf = tool[:term_frequency][term] || 0
            next if tf.zero?

            df = index[:document_frequency][term] || 0
            idf = Math.log(1 + ((total_docs - df + 0.5) / (df + 0.5)))
            normalized = (tf * (k1 + 1)) / (tf + (k1 * (1 - b + (b * (tool[:tokens].length.to_f / average_length)))))
            weight = query[:weights][term] || 1
            score += weight * idf * normalized
          end
          score
        end

        # 方法功能：计算关键词分数
        # 参数：tool - 工具索引，query - 查询
        # 返回值：包含分数和关键词的哈希
        def self.keyword_score(tool, query)
          score = 0
          keywords = []

          query[:terms].each do |term|
            next unless tool[:term_frequency].key?(term)

            keywords << term
            weight = query[:weights][term] || 1
            score += 0.8 * weight if tool[:exact_tokens].include?(term)
            score += 0.45 * weight if tool[:action_tokens].include?(term)
            score += 0.35 * weight if tool[:param_tokens].include?(term)
          end

          score += Math.sqrt(keywords.length) * 0.2 if keywords.length.positive?

          { score: score, keywords: keywords.first(10) }
        end

        # 方法功能：格式化搜索结果
        # 参数：result - 搜索结果
        # 返回值：格式化后的结果哈希
        def self.format_search_result(result)
          descriptor = result[:record].descriptor
          {
            tool_id: result[:record].tool_id,
            server_id: result[:record].server_id,
            tool_name: descriptor.name,
            title: descriptor.title || descriptor.annotations&.dig(:title),
            description: descriptor.description || '',
            score: result[:score].round(3),
            matched_keywords: result[:keywords],
            input_summary: summarize_schema(descriptor.input_schema),
            policy: result[:record].policy,
            risk: {
              read_only: descriptor.annotations&.dig(:readOnlyHint) == true,
              destructive: descriptor.annotations&.dig(:destructiveHint) == true,
              open_world: descriptor.annotations&.dig(:openWorldHint) == true
            }
          }
        end

        # 方法功能：描述记录详情
        # 参数：record - 记录
        # 返回值：详情哈希
        def self.describe_record(record)
          descriptor = record.descriptor
          result = {
            tool_id: record.tool_id,
            server_id: record.server_id,
            tool_name: descriptor.name,
            normalizedName: record.normalizedName,
            title: descriptor.title || descriptor.annotations&.dig(:title),
            description: descriptor.description || '',
            input_schema: descriptor.input_schema || { type: 'object' },
            policy: record.policy
          }

          result[:output_schema] = descriptor.output_schema if descriptor.output_schema
          result[:annotations] = descriptor.annotations if descriptor.annotations
          result[:execution] = descriptor.execution if descriptor.execution
          result[:icons] = descriptor.icons if descriptor.icons
          result[:meta] = descriptor._meta if descriptor._meta

          result
        end

        # 方法功能：从 schema 中提取文本
        # 参数：schema - schema 哈希
        # 返回值：文本字符串
        def self.extract_schema_text(schema)
          return '' unless schema.is_a?(Hash)

          pieces = []
          visit = lambda do |value, key_hint = ''|
            return unless value.is_a?(Hash)

            pieces << key_hint if key_hint.present?
            pieces << value[:title] if value[:title].is_a?(String)
            pieces << value[:description] if value[:description].is_a?(String)
            pieces << value[:enum].grep(String).join(' ') if value[:enum].is_a?(Array)

            properties = value[:properties]
            if properties.is_a?(Hash)
              properties.each do |key, child|
                pieces << key
                visit.call(child, key)
              end
            end
          end

          visit.call(schema)
          pieces.join(' ')
        end

        # 方法功能：总结 schema 摘要
        # 参数：schema - schema 哈希
        # 返回值：摘要哈希
        def self.summarize_schema(schema)
          return { required: [], parameters: [] } unless schema.is_a?(Hash)

          properties = schema[:properties].is_a?(Hash) ? schema[:properties] : {}
          {
            required: schema[:required].is_a?(Array) ? schema[:required].grep(String) : [],
            parameters: properties.keys.first(12)
          }
        end

        # 方法功能：提取动作词
        # 参数：name - 名称字符串
        # 返回值：动作词字符串
        def self.action_words(name)
          tokens = tokenize_mcp_search_text(name.gsub(%r{[._:/-]+}, ' '))
          expand_query_tokens(tokens).join(' ')
        end

        # 方法功能：重复令牌
        # 参数：tokens - 令牌数组，count - 重复次数
        # 返回值：重复后的令牌数组
        def self.repeat_tokens(tokens, count)
          tokens.flat_map { |token| [token] * count }
        end

        # 方法功能：计算词频
        # 参数：tokens - 令牌数组
        # 返回值：词频哈希
        def self.term_frequency(tokens)
          map = {}
          tokens.each { |token| map[token] = (map[token] || 0) + 1 }
          map
        end

        # 方法功能：对 MCP 搜索文本进行分词
        # 参数：text - 文本字符串
        # 返回值：令牌数组
        def self.tokenize_mcp_search_text(text = '')
          source = normalize_lower(text)
          tokens = []

          latin_terms = source.scan(/[a-z0-9][a-z0-9_-]{1,}/)
          latin_terms.each do |term|
            term.split(/[_-]+/).each do |part|
              tokens << part if token_allowed?(part)
            end
            tokens << term if token_allowed?(term)
          end

          han_segments = source.scan(/\p{Han}+/u)
          han_segments.each do |segment|
            chars = segment.chars.first(80)
            if chars.length == 1
              tokens << chars[0]
            else
              (2..[4, chars.length].min).each do |size|
                (0..(chars.length - size)).each do |index|
                  tokens << chars[index, size].join
                end
              end
            end
          end

          tokens
        end

        # 方法功能：将文本转换为小写并标准化
        # 参数：text - 文本字符串
        # 返回值：标准化后的文本
        def self.normalize_lower(text = '')
          text.to_s.unicode_normalize(:nfkc).downcase
        end

        # 方法功能：检查令牌是否允许
        # 参数：token - 令牌字符串
        # 返回值：布尔值
        def self.token_allowed?(token)
          return false if token.nil? || token.empty? || STOP_WORDS.include?(token)
          return false if token.match?(/^\d+$/)

          token.length >= 2
        end

        # 方法功能：获取字符串参数
        # 参数：value - 参数值
        # 返回值：字符串或空字符串
        def self.string_arg(value)
          value.is_a?(String) ? value.strip : ''
        end

        # 方法功能：获取数字参数
        # 参数：value - 参数值
        # 返回值：数字或 nil
        def self.number_arg(value)
          value.is_a?(Numeric) && value.finite? ? value : nil
        end

        # 方法功能：获取对象参数
        # 参数：value - 参数值
        # 返回值：哈希或空哈希
        def self.object_arg(value)
          value.is_a?(Hash) ? value : {}
        end

        # 方法功能：将值限制在正整数范围内
        # 参数：value - 输入值，fallback - 备用值，max - 最大值
        # 返回值：限制后的整数
        def self.clamp_positive_int(value, fallback, max)
          return fallback if value.nil? || value <= 0

          [value.to_i, max].min
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
