# frozen_string_literal: true

# 文件用途：Web提供者端口，提供网页抓取和搜索功能
# 使用方法：继承WebProvider类并实现fetch和search方法，支持HTTP、确定性或错误模拟实现

module DeepForge
  module Ports
    # @!method source_id_for(kind, value)
    # @!method fetch(request)
    # @!method search(request)

    # 类功能：Web提供者基类，定义网页抓取和搜索接口
    class WebProvider
      def id
        raise NotImplementedError
      end

      # @param request [WebFetchRequest]
      # @return [WebFetchResult]
      def fetch(request)
        raise NotImplementedError
      end

      # @param request [WebSearchRequest]
      # @return [Array<WebSearchResult>]
      # 方法功能：搜索网页内容
      # 参数：request - Web搜索请求对象
      # 返回值：Web搜索结果数组
      # 使用方法：传入搜索请求，返回匹配的搜索结果列表
      # @param request [WebSearchRequest]
      # @return [Array<WebSearchResult>]
      def search(request)
        raise NotImplementedError
      end
    end

    # 结构体功能：Web源数据结构
    # 使用方法：包含源ID、URL、标题和检索时间
    WebSource = Struct.new(:source_id, :url, :title, :retrieved_at, keyword_init: true)

    # 结构体功能：Web抓取请求数据结构
    # 使用方法：包含URL、最大字节数、超时毫秒数和信号
    WebFetchRequest = Struct.new(:url, :max_bytes, :timeout_ms, :signal, keyword_init: true)

    # 结构体功能：Web抓取结果数据结构
    # 使用方法：包含源ID、URL、标题、检索时间、最终URL、内容类型、文本等信息
    WebFetchResult = Struct.new(
      :source_id, :url, :title, :retrieved_at,
      :final_url, :content_type, :text, :byte_count, :truncated,
      keyword_init: true
    )

    # 结构体功能：Web搜索请求数据结构
    # 使用方法：包含查询、限制、超时毫秒数和信号
    WebSearchRequest = Struct.new(:query, :limit, :timeout_ms, :signal, keyword_init: true)

    # 结构体功能：Web搜索结果数据结构
    # 使用方法：包含源ID、URL、标题、检索时间、摘要、提供者和排名
    WebSearchResult = Struct.new(
      :source_id, :url, :title, :retrieved_at,
      :snippet, :provider, :rank,
      keyword_init: true
    )

    # 类功能：不可用Web提供者，每次调用都返回错误
    # 使用方法：作为哨兵或默认提供者，当没有真实提供者配置时使用
    class UnavailableWebProvider < WebProvider
      attr_reader :id

      def initialize(id: 'unavailable')
        @id = id
      end

      def fetch(_request)
        raise NotImplementedError, "web provider '#{@id}' is unavailable"
      end

      def search(_request)
        raise NotImplementedError, "web provider '#{@id}' is unavailable"
      end
    end

    # 类功能：确定性Web提供者，行为完全由构造函数输入驱动
    # 使用方法：适合确定性测试，传入页面和搜索结果映射
    class DeterministicWebProvider < WebProvider
      # 属性功能：获取提供者ID
      attr_reader :id

      # 方法功能：初始化确定性Web提供者
      # 参数：id - 提供者ID，now_iso - 可选时钟函数，pages - 页面映射，search_results - 搜索结果映射
      # 使用方法：传入ID、时钟函数、页面映射和搜索结果映射创建实例
      # @param id            [String]
      # @param now_iso       [Proc]  callable returning an ISO 8601 string
      # @param pages         [Hash{String => Hash}]  url → partial WebFetchResult fields
      # @param search_results [Hash{String => Array<Hash>}]  query → array of partial WebSearchResult fields
      def initialize(id: 'deterministic', now_iso: nil, pages: {}, search_results: {})
        @id = id
        @now_iso = now_iso || -> { Time.now.utc.strftime('%FT%TZ') }
        @pages = pages
        @search_results = search_results
      end

      # 方法功能：抓取指定URL的网页内容
      # 参数：request - Web抓取请求对象
      # 返回值：Web抓取结果对象
      # 使用方法：传入抓取请求，返回页面内容
      # @param request [WebFetchRequest]
      # @return [WebFetchResult]
      def fetch(request)
        page = @pages[request.url]
        raise ArgumentError, "test web page not found: #{request.url}" unless page

        bytes = page[:text].bytesize
        raise ArgumentError, "content exceeds #{request.max_bytes} byte limit" if bytes > request.max_bytes

        WebFetchResult.new(
          source_id: DeepForge::Ports.source_id_for('fetch', page[:final_url]),
          url: page[:url],
          title: page[:title],
          retrieved_at: @now_iso.call,
          final_url: page[:final_url],
          content_type: page[:content_type],
          text: page[:text],
          byte_count: bytes,
          truncated: false
        )
      end

      # 方法功能：搜索网页内容
      # 参数：request - Web搜索请求对象
      # 返回值：Web搜索结果数组
      # 使用方法：传入搜索请求，返回匹配的搜索结果
      # @param request [WebSearchRequest]
      # @return [Array<WebSearchResult>]
      def search(request)
        (@search_results[request.query] || [])
          .slice(0, request.limit)
          .each_with_index
          .map do |result, index|
            WebSearchResult.new(
              source_id: DeepForge::Ports.source_id_for('search', "#{request.query}:#{result[:url]}:#{index}"),
              url: result[:url],
              title: result[:title],
              retrieved_at: @now_iso.call,
              snippet: result[:snippet],
              provider: @id,
              rank: index + 1
            )
          end
      end
    end

    # 方法功能：生成确定性哈希源ID
    # 参数：kind - 源类型（'fetch'或'search'），value - 用于哈希的字符串值
    # 返回值：格式为"web_类型_哈希值"的字符串
    # 使用方法：传入源类型和值，生成确定性哈希ID
    # @param kind  ['fetch', 'search']
    # @param value [String]
    # @return [String]
    def self.source_id_for(kind, value)
      hash = 0
      value.each_char do |c|
        hash = (((hash << 5) - hash) + c.ord) & 0xFFFFFFFF
      end
      # Force into a signed 32-bit integer (two's complement)
      hash -= 0x100000000 if hash >= 0x80000000
      "web_#{kind}_#{hash.abs.to_s(36)}"
    end
  end
end
