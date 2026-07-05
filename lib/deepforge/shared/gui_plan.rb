# frozen_string_literal: true

# 文件用途：GUI 计划文件管理模块
# 使用方法：提供计划文件路径验证、ID 生成、输入校验等工具方法，
#           用于支持 GUI 界面中的计划创建和管理功能。

module DeepForge
  module Shared
    # GUI 计划文件相对目录（当前版本）
    GUI_PLAN_RELATIVE_DIR = '.dfsdd/plan'
    # GUI 计划文件相对目录（旧版本，兼容用）
    GUI_PLAN_LEGACY_RELATIVE_DIR = '.deepseekgui/plan'
    # 所有接受的计划文件目录列表
    GUI_PLAN_ACCEPTED_RELATIVE_DIRS = [
      GUI_PLAN_RELATIVE_DIR,
      GUI_PLAN_LEGACY_RELATIVE_DIR
    ].freeze

    # 创建计划工具的名称常量
    GUI_PLAN_CREATE_PLAN_TOOL_NAME = 'create_plan'

    # 创建计划工具的输入参数结构体
    CreatePlanToolInput = Struct.new(
      :markdown,
      :source_request,
      :title,
      :operation,
      :plan_id,
      :plan_relative_path,
      keyword_init: true
    )

    # 创建计划工具的输出结果结构体
    CreatePlanToolOutput = Struct.new(
      :summary,
      :plan_id,
      :workspace_root,
      :relative_path,
      :absolute_path,
      :source_request,
      :title,
      :operation,
      :saved_at,
      :content_hash,
      :byte_size,
      keyword_init: true
    )
    GUI_PLAN_RELATIVE_DIR = '.dfsdd/plan'
    GUI_PLAN_LEGACY_RELATIVE_DIR = '.deepseekgui/plan'
    GUI_PLAN_ACCEPTED_RELATIVE_DIRS = [
      GUI_PLAN_RELATIVE_DIR,
      GUI_PLAN_LEGACY_RELATIVE_DIR
    ].freeze

    GUI_PLAN_CREATE_PLAN_TOOL_NAME = 'create_plan'

    CreatePlanToolInput = Struct.new(
      :markdown,
      :source_request,
      :title,
      :operation,
      :plan_id,
      :plan_relative_path,
      keyword_init: true
    )

    CreatePlanToolOutput = Struct.new(
      :summary,
      :plan_id,
      :workspace_root,
      :relative_path,
      :absolute_path,
      :source_request,
      :title,
      :operation,
      :saved_at,
      :content_hash,
      :byte_size,
      keyword_init: true
    )

    # 方法功能：判断给定路径是否为有效的 GUI 计划相对路径
    # 参数：value - 待验证的文件路径字符串
    # 返回值：Boolean - 如果路径有效返回 true，否则返回 false
    def self.gui_plan_relative_path?(value)
      normalized = value.tr('\\', '/').gsub(%r{/+}, '/').sub(%r{^\./}, '').downcase
      return false unless normalized.end_with?('.md')

      matched_dir = GUI_PLAN_ACCEPTED_RELATIVE_DIRS.find do |dir|
        normalized.start_with?("#{dir}/")
      end
      return false unless matched_dir

      rest = normalized[(matched_dir.length + 1)..]
      return false if rest.nil? || rest.empty? || rest.include?('/')

      rest.split('/').none? { |part| part == '..' }
    end

    # 方法功能：判断给定路径是否为当前版本的 GUI 计划相对路径
    # 参数：value - 待验证的文件路径字符串
    # 返回值：Boolean - 如果是当前版本的计划路径返回 true，否则返回 false
    def self.gui_plan_current_relative_path?(value)
      normalized = value.tr('\\', '/').gsub(%r{/+}, '/').sub(%r{^\./}, '').downcase
      return false unless normalized.end_with?('.md')
      return false unless normalized.start_with?("#{GUI_PLAN_RELATIVE_DIR}/")

      rest = normalized[(GUI_PLAN_RELATIVE_DIR.length + 1)..]
      return false if rest.nil? || rest.empty? || rest.include?('/')

      rest.split('/').none? { |part| part == '..' }
    end

    # 方法功能：构建 GUI 计划的唯一标识符
    # 参数：workspace_root - 工作区根目录路径
    #       relative_path - 计划文件的相对路径
    # 返回值：String - 格式为 "workspace_root:relative_path" 的计划 ID
    def self.build_gui_plan_id(workspace_root, relative_path)
      ws = workspace_root.tr('\\', '/').sub(%r{/+$/}, '').downcase
      rp = relative_path.tr('\\', '/').gsub(%r{/+}, '/').sub(%r{^\./}, '').downcase
      "#{ws}:#{rp}"
    end

    # 方法功能：判断两个工作区路径是否匹配（忽略大小写和尾部斜杠）
    # 参数：actual - 实际工作区路径
    #       expected - 期望的工作区路径
    # 返回值：Boolean - 如果匹配返回 true，否则返回 false
    def self.gui_plan_workspace_matches?(actual, expected)
      actual.tr('\\', '/').sub(%r{/+$/}, '').downcase ==
        expected.tr('\\', '/').sub(%r{/+$/}, '').downcase
    end

    # 方法功能：验证创建计划工具的输入参数
    # 参数：input - 包含计划创建参数的哈希
    # 返回值：Array<String> - 错误信息列表，空列表表示验证通过
    def self.validate_create_plan_tool_input(input)
      issues = []
      unless input[:markdown].is_a?(String) && !input[:markdown].strip.empty?
        issues << 'markdown is required and must be non-empty'
      end
      issues << 'operation must be either "draft" or "refine"' unless %w[draft refine].include?(input[:operation])
      if input[:plan_relative_path]
        path = input[:plan_relative_path].to_s.strip
        if path.empty?
          issues << 'plan_relative_path must be non-empty when supplied'
        elsif !gui_plan_relative_path?(path)
          issues << 'plan_relative_path must be a direct Markdown file under .dfsdd/plan'
        end
      end
      issues << 'plan_id must be a string when supplied' if input[:plan_id] && !input[:plan_id].is_a?(String)
      issues
    end

    # 方法功能：构建计划文件的相对路径
    # 参数：feature_name - 功能名称，用作文件名
    #       suffix - 可选的后缀数字，用于区分同名文件
    # 返回值：String - 格式为 ".dfsdd/plan/feature_name[-suffix].md" 的路径
    def self.build_plan_relative_path(feature_name, suffix = nil)
      safe_suffix = suffix.is_a?(Integer) && suffix > 1 ? "-#{suffix}" : ''
      "#{GUI_PLAN_RELATIVE_DIR}/#{feature_name}#{safe_suffix}.md"
    end

    # 方法功能：获取下一个可用的计划文件相对路径
    # 参数：feature_name - 功能名称
    #       existing_relative_paths - 已存在的相对路径列表
    #       max_attempts - 最大尝试次数，默认 50
    # 返回值：String - 下一个可用的相对路径
    def self.next_available_plan_relative_path(feature_name, existing_relative_paths, max_attempts = 50)
      existing = existing_relative_paths.to_set
      (1..max_attempts).each do |attempt|
        candidate = build_plan_relative_path(feature_name, attempt)
        return candidate unless existing.include?(candidate)
      end
      build_plan_relative_path("#{feature_name}-#{Time.now.to_i}")
    end

    # 方法功能：从相对路径中提取计划的显示名称
    # 参数：relative_path - 计划文件的相对路径
    # 返回值：String - 去除 .md 后缀的文件名
    def self.plan_display_name_from_relative_path(relative_path)
      file_name = relative_path.split('/').last || ''
      file_name.sub(/\.md$/i, '') || 'plan'
    end

    # 方法功能：从用户请求中生成功能名称
    # 参数：request - 用户的请求文本
    # 返回值：String - 截断到 96 字符的功能名称
    def self.plan_feature_name_from_request(request)
      request.strip[0, 96] || 'plan'
    end
  end
end
