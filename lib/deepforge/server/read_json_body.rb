# frozen_string_literal: true

# 文件用途：JSON 请求体解析模块，将请求体解析为 Ruby 哈希并进行键符号化
# 使用方法：调用 read_json_body 方法解析 JSON 字符串，返回解析结果

module DeepForge
  module Server
    # JSON 请求体解析结果结构体
    ReadJsonBodyResult = Struct.new(:ok, :value, :response, keyword_init: true)

    # 从请求体解析 JSON 数据
    # @param body [String, nil] 原始请求体
    # @return [ReadJsonBodyResult] 解析结果，包含 :ok、:value（键已符号化）和 :response
    def self.read_json_body(body)
      return ReadJsonBodyResult.new(ok: true, value: {}, response: nil) if body.nil? || body.empty?

      begin
        value = symbolize_keys(JSON.parse(body))
        ReadJsonBodyResult.new(ok: true, value: value, response: nil)
      rescue JSON::ParserError => e
        error_body = {
          code: 'validation_error',
          message: 'invalid JSON body',
          details: e.message
        }
        ReadJsonBodyResult.new(ok: false, value: nil, response: json_response(error_body, 400))
      end
    end

    # 递归地将哈希中的字符串键转换为符号键
    # @param obj [Object] 哈希、数组或基本类型
    # @return [Object] 转换后的对象
    def self.symbolize_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize_keys(v) }
      when Array
        obj.map { |item| symbolize_keys(item) }
      else
        obj
      end
    end
  end
end
