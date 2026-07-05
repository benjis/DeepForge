# frozen_string_literal: true

# 文件用途：代码审查输出解析和渲染模块
# 使用方法：将原始审查文本解析为结构化的 ReviewOutput 对象，
#           并支持将审查结果渲染为人类可读的文本格式。

require 'json'
require_relative '../contracts/review'

module DeepForge
  module Review
    # 方法功能：将原始审查文本解析为 ReviewOutput 结构体
    # 参数：raw_text - 原始审查文本
    # 返回值：Contracts::ReviewOutput - 解析后的审查输出对象
    def self.parse_review_output(raw_text)
      text = raw_text.strip

      direct = parse_json_candidate(text)
      return direct if direct

      embedded = first_json_object(text)
      if embedded
        parsed = parse_json_candidate(embedded)
        return parsed if parsed
      end

      Contracts::ReviewOutput.new(
        findings: [],
        overall_correctness: 'patch is correct',
        overall_explanation: text.empty? ? 'Reviewer did not return a structured response.' : text,
        overall_confidence_score: 0.0
      )
    end

    # 方法功能：将 ReviewOutput 结构体渲染为人类可读的文本
    # 参数：output - 审查输出对象
    # 返回值：String - 格式化的审查结果文本
    def self.render_review_output(output)
      lines = [
        output.overall_explanation.strip.empty? ? output.overall_correctness : output.overall_explanation.strip,
        '',
        "Overall correctness: #{output.overall_correctness}",
        "Overall confidence: #{format_confidence(output.overall_confidence_score)}"
      ]

      if output.findings.empty?
        lines.push('', 'No review findings.')
        return lines.join("\n").strip
      end

      lines.push('', 'Full review comments:')
      output.findings.each do |finding|
        lines.push('', format_finding_header(finding), indent_body(finding.body))
      end

      lines.join("\n").strip
    end

    class << self
      private

      # 方法功能：尝试解析 JSON 字符串为审查输出
      # 参数：candidate - 待解析的 JSON 字符串
      # 返回值：Contracts::ReviewOutput 或 nil - 解析成功返回对象，否则返回 nil
      def parse_json_candidate(candidate)
        return nil if candidate.nil? || candidate.empty?

        parsed = JSON.parse(candidate)
        normalize_and_build(parsed)
      rescue JSON::ParserError
        nil
      end

      # 方法功能：标准化原始 JSON 数据并构建审查输出对象
      # 参数：raw - 解析后的 JSON 哈希
      # 返回值：Contracts::ReviewOutput - 标准化后的审查输出对象
      def normalize_and_build(raw)
        findings = Array(raw['findings']).map { |f| normalize_finding(f) }

        Contracts::ReviewOutput.new(
          findings: findings,
          overall_correctness: raw['overallCorrectness'] || raw['overall_correctness'] || 'patch is correct',
          overall_explanation: raw['overallExplanation'] || raw['overall_explanation'] || '',
          overall_confidence_score: raw['overallConfidenceScore'] || raw['overall_confidence_score'] || 0
        )
      end

      # 方法功能：标准化单个审查发现
      # 参数：raw - 原始发现数据哈希
      # 返回值：Contracts::ReviewFinding - 标准化后的发现对象
      def normalize_finding(raw)
        location = raw['codeLocation'] || raw['code_location']
        Contracts::ReviewFinding.new(
          title: raw['title'] || '',
          body: raw['body'] || '',
          confidence_score: raw['confidenceScore'] || raw['confidence_score'] || 0,
          priority: raw['priority'] || priority_from_title(raw['title']),
          code_location: normalize_code_location(location)
        )
      end

      # 方法功能：标准化代码位置信息
      # 参数：raw - 原始位置数据哈希
      # 返回值：Contracts::ReviewCodeLocation 或 nil - 标准化后的代码位置对象
      def normalize_code_location(raw)
        return nil unless raw.is_a?(Hash)

        line_range_raw = raw['lineRange'] || raw['line_range']
        Contracts::ReviewCodeLocation.new(
          absolute_file_path: raw['absoluteFilePath'] || raw['absolute_file_path'] || '',
          line_range: normalize_line_range(line_range_raw)
        )
      end

      # 方法功能：标准化行范围信息
      # 参数：raw - 原始行范围数据哈希
      # 返回值：Contracts::ReviewLineRange 或 nil - 标准化后的行范围对象
      def normalize_line_range(raw)
        return nil unless raw.is_a?(Hash)

        Contracts::ReviewLineRange.new(
          start: raw['start'],
          end: raw['end'] || raw['start']
        )
      end

      # 方法功能：从标题中提取优先级
      # 参数：value - 发现标题字符串
      # 返回值：Integer - 优先级数字（0-3），默认为 2
      def priority_from_title(value)
        return 2 unless value.is_a?(String)

        match = value.match(/\[P([0-3])\]/i)
        match ? match[1].to_i : 2
      end

      # 方法功能：从文本中提取第一个完整的 JSON 对象
      # 参数：text - 待搜索的文本
      # 返回值：String 或 nil - 提取的 JSON 对象字符串，未找到返回 nil
      def first_json_object(text)
        start_idx = text.index('{')
        return nil unless start_idx

        depth = 0
        in_string = false
        escaping = false

        (start_idx...text.length).each do |index|
          char = text[index]
          if escaping
            escaping = false
            next
          end
          if char == '\\' && in_string
            escaping = true
            next
          end
          if char == '"'
            in_string = !in_string
            next
          end
          next if in_string

          depth += 1 if char == '{'
          if char == '}'
            depth -= 1
            return text[start_idx..index] if depth.zero?
          end
        end

        nil
      end

      # 方法功能：格式化审查发现的标题行
      # 参数：finding - 审查发现对象
      # 返回值：String - 格式化的标题行（包含文件路径和行号）
      def format_finding_header(finding)
        loc = finding.code_location
        range = loc&.line_range
        "- #{finding.title} -- #{loc&.absolute_file_path}:#{range&.start}-#{range&.end}"
      end

      # 方法功能：缩进审查发现的正文内容
      # 参数：body - 正文文本
      # 返回值：String - 缩进后的文本
      def indent_body(body)
        text = body.strip
        return '  No details provided.' if text.empty?

        text.split("\n").map { |line| "  #{line}" }.join("\n")
      end

      # 方法功能：格式化置信度分数
      # 参数：value - 置信度数值
      # 返回值：String - 格式化后的置信度字符串（如 "0.85"）
      def format_confidence(value)
        value.is_a?(Numeric) && value.finite? ? format('%.2f', value) : '0.00'
      end
    end
  end
end
