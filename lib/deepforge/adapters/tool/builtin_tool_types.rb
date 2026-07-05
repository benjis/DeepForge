# frozen_string_literal: true

# 文件用途：内置工具的类型定义和常量配置
# 使用方法：定义所有工具共享的数据结构、常量和选项类型

require 'fileutils'

module DeepForge
  module Adapters
    module Tool
      # 默认 bash 命令超时时间（秒）
      DEFAULT_BASH_TIMEOUT_SECONDS = 120

      # 各工具的默认结果限制
      DEFAULT_SEARCH_LIMIT = 100
      DEFAULT_LIST_LIMIT = 500
      DEFAULT_FIND_LIMIT = 1000

      # 图片处理默认配置
      DEFAULT_IMAGE_MAX_DIMENSION = 2000
      DEFAULT_IMAGE_MAX_BASE64_BYTES = 4.5 * 1024 * 1024

      # fd 和 rg 可执行文件的候选路径
      FD_EXECUTABLE_CANDIDATES = [
        '/Applications/Codex.app/Contents/Resources/fd',
        'fd'
      ].freeze

      RG_EXECUTABLE_CANDIDATES = [
        '/Applications/Codex.app/Contents/Resources/rg',
        'rg'
      ].freeze

      # 紧凑资源文件名集合（用于读取分类）
      COMPACT_RESOURCE_FILE_NAMES = Set.new(%w[AGENTS.md AGENTS.MD CLAUDE.md CLAUDE.MD])

      # 所有内置工具名称集合
      ALL_BUILTIN_TOOL_NAMES = Set.new(%w[read bash edit write grep find ls]).freeze
      ALL_TOOL_NAMES = ALL_BUILTIN_TOOL_NAMES

      # 文本切片结构体，用于描述截断后的输出信息
      TextSlice = Struct.new(
        :text, :truncated, :total_lines, :shown_lines,
        :total_bytes, :shown_bytes, :first_line_exceeds_limit,
        :truncated_by, :last_line_partial,
        keyword_init: true
      )

      # Shell 配置结构体
      ShellConfig = Struct.new(:shell, :args, keyword_init: true)

      # 目录列表条目结构体
      ListEntry = Struct.new(:path, :relative_path, :name, :kind, :size, keyword_init: true)

      # Grep 匹配结果结构体
      GrepMatch = Struct.new(
        :path, :relative_path, :line, :column, :text,
        :context_before, :context_after,
        keyword_init: true
      )

      # 编辑指令结构体
      EditInstruction = Struct.new(:old_text, :new_text, keyword_init: true)

      # 图片检测结果结构体
      ImageDetection = Struct.new(:mime_type, :width, :height, keyword_init: true)

      # 特殊文件的读取分类结构体
      ReadClassification = Struct.new(:kind, :label, keyword_init: true)

      # 读取工具选项结构体
      ReadLocalToolOptions = Struct.new(
        :max_lines, :max_bytes, :auto_resize_images, :operations,
        keyword_init: true
      )

      # Bash 工具选项结构体
      BashLocalToolOptions = Struct.new(:default_timeout_seconds, :operations, keyword_init: true)

      # 写入工具选项结构体
      WriteLocalToolOptions = Struct.new(:operations, keyword_init: true)

      # 编辑工具选项结构体
      EditLocalToolOptions = Struct.new(:operations, keyword_init: true)

      # 搜索工具选项结构体
      GrepLocalToolOptions = Struct.new(:default_limit, :rg_executable_candidates, :operations, keyword_init: true)

      # 查找工具选项结构体
      FindLocalToolOptions = Struct.new(
        :default_limit, :fd_executable_candidates, :rg_executable_candidates, :operations,
        keyword_init: true
      )

      # 列表工具选项结构体
      LsLocalToolOptions = Struct.new(:default_limit, :operations, keyword_init: true)

      # 所有内置工具的组合选项结构体
      BuiltinLocalToolsOptions = Struct.new(
        :read, :bash, :write, :edit, :grep, :find, :ls,
        keyword_init: true
      )

      ToolsOptions = BuiltinLocalToolsOptions

      # 读取工具操作接口结构体
      ReadLocalToolOperations = Struct.new(:stat, :read_file, :detect_image_mime_type, :resize_image,
                                           keyword_init: true)

      # Bash 工具操作接口结构体
      BashLocalToolOperations = Struct.new(:exec, keyword_init: true)

      # 写入工具操作接口结构体
      WriteLocalToolOperations = Struct.new(:mkdir, :write_file, keyword_init: true)

      # 编辑工具操作接口结构体
      EditLocalToolOperations = Struct.new(:read_file, :write_file, keyword_init: true)

      # 搜索工具操作接口结构体
      GrepLocalToolOperations = Struct.new(:search, keyword_init: true)

      # 查找工具操作接口结构体
      FindLocalToolOperations = Struct.new(:glob, keyword_init: true)

      # 列表工具操作接口结构体
      LsLocalToolOperations = Struct.new(:stat, :readdir, keyword_init: true)
    end
  end
end
