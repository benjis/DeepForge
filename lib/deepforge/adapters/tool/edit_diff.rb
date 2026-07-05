# frozen_string_literal: true

# 文件用途：文件编辑差异处理模块
# 使用方法：提供模糊匹配、差异生成、补丁生成等文件编辑相关功能

require 'diff/lcs'
require 'diff/lcs/hunk'

module DeepForge
  module Adapters
    module Tool
      # 编辑指令结构体，包含 old_text 和 new_text
      Edit = Struct.new(:old_text, :new_text, keyword_init: true)

      # 模糊匹配结果结构体
      FuzzyMatchResult = Struct.new(
        :found, :index, :match_length, :used_fuzzy_match, :content_for_replacement,
        keyword_init: true
      )

      # 匹配后的编辑指令结构体（内部使用）
      MatchedEdit = Struct.new(:edit_index, :match_index, :match_length, :new_text, keyword_init: true)

      # 应用编辑后的结果结构体
      AppliedEditsResult = Struct.new(:base_content, :new_content, keyword_init: true)

      # 编辑差异结果结构体
      EditDiffResult = Struct.new(:diff, :first_changed_line, keyword_init: true)

      # 编辑差异错误结构体
      EditDiffError = Struct.new(:error, keyword_init: true)

      # 模块功能：提供文件编辑差异处理，包括模糊匹配、差异生成和补丁生成
      module EditDiff
        # 方法功能：检测文本的换行符风格
        # 参数：content - 文本内容
        # 返回值：'\r\n' 或 '\n'
        def self.detect_line_ending(content)
          crlf_index = content.index("\r\n")
          lf_index = content.index("\n")

          return "\n" if lf_index.nil?
          return "\n" if crlf_index.nil?

          crlf_index < lf_index ? "\r\n" : "\n"
        end

        # Normalize line endings to LF.
        # @param text [String]
        # @return [String]
        # 方法功能：将换行符标准化为 LF
        # 参数：text - 文本内容
        # 返回值：标准化后的文本
        def self.normalize_to_lf(text)
          text.gsub("\r\n", "\n").gsub("\r", "\n")
        end

        # Restore line endings.
        # @param text [String]
        # @param ending [String]
        # @return [String]
        # 方法功能：恢复文本的换行符风格
        # 参数：text - 文本内容，ending - 目标换行符
        # 返回值：恢复换行符后的文本
        def self.restore_line_endings(text, ending)
          ending == "\r\n" ? text.gsub("\n", "\r\n") : text
        end

        # Strip BOM from content.
        # @param content [String]
        # @return [Hash] with :bom and :text
        # 方法功能：移除文本的 BOM（字节顺序标记）
        # 参数：content - 文本内容
        # 返回值：包含 :bom 和 :text 的哈希
        def self.strip_bom(content)
          if content.start_with?("\uFEFF")
            { bom: "\uFEFF", text: content[1..] }
          else
            { bom: '', text: content }
          end
        end

        # Normalize text for fuzzy matching.
        # @param text [String]
        # @return [String]
        # 方法功能：为模糊匹配标准化文本
        # 参数：text - 文本内容
        # 返回值：标准化后的文本
        def self.normalize_for_fuzzy_match(text)
          text
            .unicode_normalize(:nfkc)
            .split("\n")
            .map(&:rstrip)
            .join("\n")
            .gsub(/[\u2018\u2019\u201A\u201B]/, "'")
            .gsub(/[\u201C\u201D\u201E\u201F]/, '"')
            .gsub(/[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]/, '-')
            .gsub(/[\u00A0\u2002-\u200A\u202F\u205F\u3000]/, ' ')
        end

        # Find text in content with fuzzy matching.
        # @param content [String]
        # @param old_text [String]
        # @return [FuzzyMatchResult]
        # 方法功能：在内容中模糊查找文本
        # 参数：content - 内容字符串，old_text - 要查找的文本
        # 返回值：FuzzyMatchResult 结构体
        def self.fuzzy_find_text(content, old_text)
          exact_index = content.index(old_text)
          if exact_index
            return FuzzyMatchResult.new(
              found: true,
              index: exact_index,
              match_length: old_text.length,
              used_fuzzy_match: false,
              content_for_replacement: content
            )
          end

          fuzzy_content = normalize_for_fuzzy_match(content)
          fuzzy_old_text = normalize_for_fuzzy_match(old_text)
          fuzzy_index = fuzzy_content.index(fuzzy_old_text)

          if fuzzy_index.nil?
            return FuzzyMatchResult.new(
              found: false,
              index: -1,
              match_length: 0,
              used_fuzzy_match: false,
              content_for_replacement: content
            )
          end

          FuzzyMatchResult.new(
            found: true,
            index: fuzzy_index,
            match_length: fuzzy_old_text.length,
            used_fuzzy_match: true,
            content_for_replacement: fuzzy_content
          )
        end

        # Apply edits to normalized content.
        # @param normalized_content [String]
        # @param edits [Array<Edit>]
        # @param path [String]
        # @return [AppliedEditsResult]
        # 方法功能：将编辑指令应用到标准化内容
        # 参数：normalized_content - 标准化后的内容，edits - 编辑指令数组，path - 文件路径
        # 返回值：AppliedEditsResult 结构体
        def self.apply_edits_to_normalized_content(normalized_content, edits, path)
          normalized_edits = edits.map do |edit|
            Edit.new(old_text: normalize_to_lf(edit.old_text), new_text: normalize_to_lf(edit.new_text))
          end

          normalized_edits.each_with_index do |edit, index|
            raise empty_old_text_error(path, index, normalized_edits.length) if edit.old_text.empty?
          end

          initial_matches = normalized_edits.map { |edit| fuzzy_find_text(normalized_content, edit.old_text) }
          base_content = initial_matches.any?(&:used_fuzzy_match) ? normalize_for_fuzzy_match(normalized_content) : normalized_content

          matched_edits = []
          normalized_edits.each_with_index do |edit, index|
            match_result = fuzzy_find_text(base_content, edit.old_text)
            raise not_found_error(path, index, normalized_edits.length) unless match_result.found

            occurrences = count_occurrences(base_content, edit.old_text)
            raise duplicate_error(path, index, normalized_edits.length, occurrences) if occurrences > 1

            matched_edits << MatchedEdit.new(
              edit_index: index,
              match_index: match_result.index,
              match_length: match_result.match_length,
              new_text: edit.new_text
            )
          end

          matched_edits.sort_by!(&:match_index)
          matched_edits.each_cons(2) do |previous, current|
            if previous.match_index + previous.match_length > current.match_index
              raise "edits[#{previous.edit_index}] and edits[#{current.edit_index}] overlap in #{path}. Merge them into one edit or target disjoint regions."
            end
          end

          new_content = base_content.dup
          matched_edits.sort_by { |e| -e.match_index }.each do |edit|
            new_content = "#{new_content[0...edit.match_index]}#{edit.new_text}#{new_content[(edit.match_index + edit.match_length)..]}"
          end

          raise no_change_error(path, normalized_edits.length) if base_content == new_content

          AppliedEditsResult.new(base_content: base_content, new_content: new_content)
        end

        # Find the first changed line between two contents.
        # @param old_content [String]
        # @param new_content [String]
        # @return [Integer, nil]
        # 方法功能：查找第一个变更的行号
        # 参数：old_content - 旧内容，new_content - 新内容
        # 返回值：行号（从1开始）或 nil
        def self.first_changed_line(old_content, new_content)
          old_lines = old_content.split("\n")
          new_lines = new_content.split("\n")
          count = [old_lines.length, new_lines.length].max

          count.times do |index|
            return index + 1 if (old_lines[index] || '') != (new_lines[index] || '')
          end

          nil
        end

        # Generate a display diff.
        # @param old_content [String]
        # @param new_content [String]
        # @param context_lines [Integer]
        # @return [String]
        # 方法功能：生成显示用的差异文本
        # 参数：old_content - 旧内容，new_content - 新内容，context_lines - 上下文行数
        # 返回值：差异文本字符串
        def self.generate_display_diff(old_content, new_content, _context_lines = 4)
          diffs = Diff::LCS.sdiff(old_content.split("\n"), new_content.split("\n"))
          output = []

          old_line_num = 1
          new_line_num = 1

          diffs.each do |diff|
            case diff.action
            when '='
              output << " #{format_line_num(old_line_num, 0)} #{diff.old_element}"
              old_line_num += 1
              new_line_num += 1
            when '+'
              output << "+#{format_line_num(new_line_num, 0)} #{diff.new_element}"
              new_line_num += 1
            when '-'
              output << "-#{format_line_num(old_line_num, 0)} #{diff.old_element}"
              old_line_num += 1
            when '!'
              output << "-#{format_line_num(old_line_num, 0)} #{diff.old_element}"
              output << "+#{format_line_num(new_line_num, 0)} #{diff.new_element}"
              old_line_num += 1
              new_line_num += 1
            end
          end

          output.join("\n")
        end

        # Generate diff string with metadata.
        # @param old_content [String]
        # @param new_content [String]
        # @param context_lines [Integer]
        # @return [EditDiffResult]
        # 方法功能：生成带元数据的差异字符串
        # 参数：old_content - 旧内容，new_content - 新内容，context_lines - 上下文行数
        # 返回值：EditDiffResult 结构体
        def self.generate_diff_string(old_content, new_content, context_lines = 4)
          EditDiffResult.new(
            diff: generate_display_diff(old_content, new_content, context_lines),
            first_changed_line: first_changed_line(old_content, new_content)
          )
        end

        # Generate unified patch.
        # @param path [String]
        # @param old_content [String]
        # @param new_content [String]
        # @param context_lines [Integer]
        # @return [String]
        # 方法功能：生成统一补丁格式的差异
        # 参数：path - 文件路径，old_content - 旧内容，new_content - 新内容，context_lines - 上下文行数
        # 返回值：统一补丁字符串
        def self.generate_unified_patch(path, old_content, new_content, context_lines = 4)
          old_lines = old_content.split("\n")
          new_lines = new_content.split("\n")

          hunk = Diff::LCS::Hunk.new(
            old_lines,
            new_lines,
            context_lines,
            0
          )

          header = "--- a/#{path}\n+++ b/#{path}\n"
          header + hunk.diff(:unified)
        end

        # Compute edits diff from file.
        # @param path [String]
        # @param edits [Array<Edit>]
        # @param cwd [String]
        # @return [EditDiffResult, EditDiffError]
        # 方法功能：计算文件编辑的差异
        # 参数：path - 文件路径，edits - 编辑指令数组，cwd - 工作目录
        # 返回值：EditDiffResult 或 EditDiffError 结构体
        def self.compute_edits_diff(path, edits, cwd)
          absolute_path = File.expand_path(path, cwd)
          raw_content = File.read(absolute_path)
          content_data = strip_bom(raw_content)
          normalized_content = normalize_to_lf(content_data[:text])
          result = apply_edits_to_normalized_content(normalized_content, edits, path)
          generate_diff_string(result.base_content, result.new_content)
        rescue StandardError => e
          EditDiffError.new(error: e.message)
        end

        # Compute single edit diff from file.
        # @param path [String]
        # @param old_text [String]
        # @param new_text [String]
        # @param cwd [String]
        # @return [EditDiffResult, EditDiffError]
        # 方法功能：计算单个编辑的差异
        # 参数：path - 文件路径，old_text - 旧文本，new_text - 新文本，cwd - 工作目录
        # 返回值：EditDiffResult 或 EditDiffError 结构体
        def self.compute_edit_diff(path, old_text, new_text, cwd)
          compute_edits_diff(path, [Edit.new(old_text: old_text, new_text: new_text)], cwd)
        end

        class << self
          private

          # Count occurrences of old_text in content.
          # @param content [String]
          # @param old_text [String]
          # @return [Integer]
          # 方法功能：计算文本在内容中出现的次数
          # 参数：content - 内容字符串，old_text - 要查找的文本
          # 返回值：出现次数
          def count_occurrences(content, old_text)
            fuzzy_content = normalize_for_fuzzy_match(content)
            fuzzy_old_text = normalize_for_fuzzy_match(old_text)
            fuzzy_content.split(fuzzy_old_text).length - 1
          end

          # Format line number with padding.
          # @param num [Integer]
          # @param width [Integer]
          # @return [String]
          # 方法功能：格式化行号
          # 参数：num - 行号，width - 宽度
          # 返回值：格式化后的行号字符串
          def format_line_num(num, width)
            num.to_s.rjust(width)
          end

          # Error for empty old text.
          # 方法功能：生成旧文本为空的错误消息
          # 参数：path - 文件路径，edit_index - 编辑索引，total_edits - 总编辑数
          # 返回值：错误消息字符串
          def empty_old_text_error(path, edit_index, total_edits)
            if total_edits == 1
              "oldText must not be empty in #{path}."
            else
              "edits[#{edit_index}].oldText must not be empty in #{path}."
            end
          end

          # Error for text not found.
          # 方法功能：生成文本未找到的错误消息
          # 参数：path - 文件路径，edit_index - 编辑索引，total_edits - 总编辑数
          # 返回值：错误消息字符串
          def not_found_error(path, edit_index, total_edits)
            if total_edits == 1
              "Could not find the exact text in #{path}. The old text must match exactly including all whitespace and newlines."
            else
              "Could not find edits[#{edit_index}] in #{path}. The oldText must match exactly including all whitespace and newlines."
            end
          end

          # Error for duplicate text.
          # 方法功能：生成重复文本的错误消息
          # 参数：path - 文件路径，edit_index - 编辑索引，total_edits - 总编辑数，occurrences - 出现次数
          # 返回值：错误消息字符串
          def duplicate_error(path, edit_index, total_edits, occurrences)
            if total_edits == 1
              "Found #{occurrences} occurrences of the text in #{path}. The text must be unique. Please provide more context to make it unique."
            else
              "Found #{occurrences} occurrences of edits[#{edit_index}] in #{path}. Each oldText must be unique. Please provide more context to make it unique."
            end
          end

          # Error for no change.
          # 方法功能：生成无变更的错误消息
          # 参数：path - 文件路径，total_edits - 总编辑数
          # 返回值：错误消息字符串
          def no_change_error(path, total_edits)
            if total_edits == 1
              "No changes made to #{path}. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
            else
              "No changes made to #{path}. The replacements produced identical content."
            end
          end
        end
      end
    end
  end
end
