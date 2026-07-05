# frozen_string_literal: true

# 文件用途：技能（Skill）运行时管理模块
# 使用方法：负责技能的加载、匹配、注入和诊断，
#           支持通过命令、提示词模式、文件类型等触发技能激活。

require 'json'
require 'fileutils'
require 'time'

module DeepForge
  module Skills
    # 默认最大同时激活技能数量
    DEFAULT_ACTIVE_LIMIT = 3
    # 默认指令注入字节预算
    DEFAULT_INSTRUCTION_BUDGET_BYTES = 24_000

    # 技能触发器清单结构体，从 skill.json 解析
    SkillTriggerManifest = Struct.new(:commands, :prompt_patterns, :file_types, keyword_init: true) do
      def self.default
        new(commands: [], prompt_patterns: [], file_types: [])
      end
    end

    # 技能清单结构体，从 skill.json 解析
    SkillManifest = Struct.new(
      :id, :name, :description, :version, :entry,
      :triggers, :allowed_tools, :assets, :priority,
      keyword_init: true
    ) do
      # 方法功能：从哈希创建技能清单
      # 参数：attrs - 包含技能属性的哈希
      # 返回值：SkillManifest - 技能清单对象
      def self.from_hash(attrs)
        triggers = attrs[:triggers] || {}
        new(
          id: attrs[:id],
          name: attrs[:name],
          description: attrs[:description],
          version: attrs[:version] || '0.0.0',
          entry: attrs[:entry] || 'SKILL.md',
          triggers: SkillTriggerManifest.new(
            commands: triggers[:commands] || [],
            prompt_patterns: triggers[:prompt_patterns] || [],
            file_types: triggers[:file_types] || []
          ),
          allowed_tools: attrs[:allowed_tools] || [],
          assets: attrs[:assets] || [],
          priority: attrs[:priority] || 0
        )
      end
    end

    # 已加载的技能结构体，包含解析后的路径和内容
    LoadedSkill = Struct.new(
      :id, :name, :description, :version, :root,
      :entry_path, :entry, :triggers, :allowed_tools,
      :assets, :priority, :legacy,
      keyword_init: true
    )

    # 技能激活记录结构体
    SkillActivation = Struct.new(:skill_id, :reason, :score, keyword_init: true)

    # 技能匹配结果结构体
    SkillTurnResolution = Struct.new(
      :active_skill_ids, :activations, :instructions,
      :allowed_tool_names, :injected_bytes,
      keyword_init: true
    )

    # 技能运行时类，负责加载、匹配和注入技能
    class SkillRuntime
      # 方法功能：创建技能运行时实例
      # 参数：config - 技能能力配置哈希
      #       options - 运行时选项（active_limit、instruction_budget_bytes）
      # 返回值：SkillRuntime - 技能运行时实例
      def self.create(config = nil, options = {})
        normalized = config || { enabled: false, roots: [], legacy_skill_md: true }
        resolved_options = {
          active_limit: options[:active_limit] || DEFAULT_ACTIVE_LIMIT,
          instruction_budget_bytes: options[:instruction_budget_bytes] || DEFAULT_INSTRUCTION_BUDGET_BYTES
        }
        loaded = normalized[:enabled] ? discover_skills(normalized) : { skills: [], validation_errors: [] }
        new(normalized, resolved_options, loaded)
      end

      def initialize(config, options, loaded)
        @config = config
        @options = options
        @skills = loaded[:skills]
        @validation_errors = loaded[:validation_errors]
        @last_activations = []
        @last_injection = nil
      end

      # 方法功能：从磁盘刷新技能列表
      # 返回值：void
      def refresh
        loaded = @config[:enabled] ? discover_skills(@config) : { skills: [], validation_errors: [] }
        @skills = loaded[:skills]
        @validation_errors = loaded[:validation_errors]
      end

      # 方法功能：解析当前回合应激活的技能
      # 参数：prompt - 用户提示词
      #       workspace - 工作区路径
      #       file_paths - 可选的文件路径列表
      # 返回值：SkillTurnResolution - 技能匹配结果
      def resolve_turn(prompt:, workspace:, file_paths: nil)
        return self.class.empty_resolution unless @config[:enabled]

        matches = match_skills(prompt, workspace, file_paths)
        active = matches.first(@options[:active_limit])
        injection = build_injection(active, @options[:instruction_budget_bytes])
        blocked = blocked_tools(@skills, injection[:allowed_tool_names])

        @last_activations = active.map do |m|
          SkillActivation.new(skill_id: m[:skill].id, reason: m[:reason], score: m[:score])
        end
        @last_injection = {
          active_skill_ids: injection[:active_skill_ids],
          injected_bytes: injection[:injected_bytes],
          budget_bytes: @options[:instruction_budget_bytes],
          blocked_tool_names: blocked
        }

        SkillTurnResolution.new(
          active_skill_ids: injection[:active_skill_ids],
          activations: @last_activations,
          instructions: injection[:instructions],
          allowed_tool_names: injection[:allowed_tool_names],
          injected_bytes: injection[:injected_bytes]
        )
      end

      # 方法功能：获取已加载技能的诊断信息
      # 返回值：Hash - 包含技能配置、加载状态、验证错误等诊断数据
      def diagnostics
        {
          enabled: @config[:enabled],
          roots: @config[:roots].dup,
          skills: @skills.map do |skill|
            {
              id: skill.id,
              name: skill.name,
              root: skill.root,
              legacy: skill.legacy,
              triggers: skill.triggers.to_h.transform_keys { |k| k.to_s.to_sym },
              allowed_tools: skill.allowed_tools
            }
          end,
          validation_errors: @validation_errors.dup,
          last_activations: @last_activations.map(&:to_h),
          last_injection: @last_injection
        }
      end

      # 方法功能：获取已加载技能的数量
      # 返回值：Integer - 技能数量
      def count
        @skills.length
      end

      private

      # 方法功能：匹配当前回合应激活的技能
      # 参数：prompt - 用户提示词
      #       workspace - 工作区路径
      #       file_paths - 可选的文件路径列表
      # 返回值：Array<Hash> - 匹配的技能列表，按分数排序
      def match_skills(prompt, _workspace, file_paths)
        lower_prompt = prompt.downcase
        file_types = self.class.file_types_from(file_paths || [], prompt)
        matches = []

        @skills.each do |skill|
          explicit = explicit_skill_mention(skill, prompt)
          if explicit
            matches << { skill: skill, skill_id: skill.id, reason: explicit, score: 1000 + skill.priority }
            next
          end

          command = skill.triggers.commands.find { |c| lower_prompt.start_with?(c.downcase) }
          if command
            matches << { skill: skill, skill_id: skill.id, reason: "command:#{command}", score: 900 + skill.priority }
            next
          end

          pattern = skill.triggers.prompt_patterns.find { |p| safe_pattern_matches(p, prompt) }
          if pattern
            matches << { skill: skill, skill_id: skill.id, reason: "pattern:#{pattern}", score: 500 + skill.priority }
            next
          end

          file_type = skill.triggers.file_types.find { |ft| file_types.include?(normalize_file_type(ft)) }
          if file_type
            matches << { skill: skill, skill_id: skill.id, reason: "fileType:#{file_type}",
                         score: 300 + skill.priority }
          end
        end

        matches.sort_by { |m| [-m[:score], m[:skill].id] }
      end

      # 方法功能：从配置中发现并加载所有技能
      # 参数：config - 技能配置哈希
      # 返回值：Hash - 包含 skills 和 validation_errors 的哈希
      def self.discover_skills(config)
        skills = []
        validation_errors = []
        config[:roots].each do |raw_root|
          root = ::File.expand_path(raw_root)
          candidates = package_candidates(root)
          candidates.each do |candidate|
            loaded = load_skill_package(candidate, config[:legacy_skill_md])
            skills << loaded if loaded
          rescue StandardError => e
            validation_errors << { root: candidate, message: error_message(e) }
          end
        rescue StandardError => e
          validation_errors << { root: raw_root, message: error_message(e) }
        end

        unique = {}
        skills.each do |skill|
          if unique[skill.id]
            validation_errors << { root: skill.root, message: "duplicate Skill id: #{skill.id}" }
          else
            unique[skill.id] = skill
          end
        end

        { skills: unique.values.sort_by(&:id), validation_errors: validation_errors }
      end

      # 方法功能：查找技能根目录下的候选技能包
      # 参数：root - 技能根目录路径
      # 返回值：Array<String> - 候选技能包路径列表
      def self.package_candidates(root)
        candidates = []
        candidates << root if ::File.exist?(::File.join(root,
                                                        'skill.json')) || ::File.exist?(::File.join(root, 'SKILL.md'))

        Dir.children(root).each do |name|
          dir = ::File.join(root, name)
          next unless ::File.directory?(dir)
          next unless ::File.exist?(::File.join(dir, 'skill.json')) || ::File.exist?(::File.join(dir, 'SKILL.md'))

          candidates << dir
        end
        candidates
      end

      # 方法功能：加载单个技能包
      # 参数：root - 技能包根目录路径
      #       allow_legacy - 是否允许加载旧版 SKILL.md 格式
      # 返回值：LoadedSkill 或 nil - 加载成功返回技能对象，否则返回 nil
      def self.load_skill_package(root, allow_legacy)
        manifest_path = ::File.join(root, 'skill.json')
        if ::File.exist?(manifest_path)
          raw = JSON.parse(::File.read(manifest_path), symbolize_names: true)
          manifest = SkillManifest.from_hash(raw)
          entry_path = ::File.expand_path(manifest.entry, root)
          entry = ::File.read(entry_path)
          assets = manifest.assets.map { |asset| ::File.expand_path(asset, root) }
          return LoadedSkill.new(
            id: slug(manifest.id || manifest.name),
            name: manifest.name,
            description: manifest.description,
            version: manifest.version,
            root: root,
            entry_path: entry_path,
            entry: entry,
            triggers: manifest.triggers,
            allowed_tools: manifest.allowed_tools,
            assets: assets,
            priority: manifest.priority,
            legacy: false
          )
        end

        return nil unless allow_legacy

        legacy_path = ::File.join(root, 'SKILL.md')
        return nil unless ::File.exist?(legacy_path)

        entry = ::File.read(legacy_path)
        name = ::File.basename(root)
        LoadedSkill.new(
          id: slug(name),
          name: name,
          description: first_markdown_paragraph(entry),
          version: 'legacy',
          root: root,
          entry_path: legacy_path,
          entry: entry,
          triggers: SkillTriggerManifest.default,
          allowed_tools: [],
          assets: [],
          priority: 0,
          legacy: true
        )
      end

      # 方法功能：构建技能注入内容
      # 参数：active - 激活的技能列表
      #       budget_bytes - 指令注入字节预算
      # 返回值：Hash - 包含指令文本、允许工具等注入信息
      def build_injection(active, budget_bytes)
        instructions = []
        active_skill_ids = []
        allowed = {}
        injected_bytes = 0

        active.each do |match|
          skill = match[:skill]
          parts = []
          parts << "Active Skill: #{skill.name} (#{skill.id})"
          parts << "Activation: #{match[:reason]}"
          parts << "Description: #{skill.description}" if skill.description
          parts << "Allowed tools: #{skill.allowed_tools.join(', ')}" unless skill.allowed_tools.empty?
          parts << "Assets:\n#{skill.assets.map { |a| "- #{a}" }.join("\n")}" if skill.assets.any?
          parts << skill.entry

          text = parts.reject(&:empty?).join("\n\n")
          bytes = text.bytesize
          next if injected_bytes + bytes > budget_bytes

          active_skill_ids << skill.id
          instructions << text
          injected_bytes += bytes
          skill.allowed_tools.each { |t| allowed[t] = true }
        end

        {
          active_skill_ids: active_skill_ids,
          instructions: instructions,
          allowed_tool_names: allowed.any? ? allowed.keys.sort : nil,
          injected_bytes: injected_bytes
        }
      end

      # 方法功能：计算被阻止的工具列表
      # 参数：skills - 所有已加载技能
      #       allowed_tool_names - 允许的工具名称列表
      # 返回值：Array<String> - 被阻止的工具名称列表
      def blocked_tools(skills, allowed_tool_names)
        return [] unless allowed_tool_names

        allowed = allowed_tool_names.to_set
        all_tools = skills.flat_map(&:allowed_tools).uniq
        all_tools.reject { |t| allowed.include?(t) }.sort
      end

      # 方法功能：创建空的技能匹配结果
      # 返回值：SkillTurnResolution - 空的匹配结果
      def self.empty_resolution
        SkillTurnResolution.new(
          active_skill_ids: [],
          activations: [],
          instructions: [],
          allowed_tool_names: nil,
          injected_bytes: 0
        )
      end

      # 方法功能：检测提示词中是否显式提到了技能
      # 参数：skill - 技能对象
      #       prompt - 用户提示词
      # 返回值：String 或 nil - 匹配原因（如 "explicit:id"），未匹配返回 nil
      def explicit_skill_mention(skill, prompt)
        lower = prompt.downcase
        id = skill.id.downcase
        name = skill.name.downcase

        return 'explicit:id' if lower.include?("$#{id}") || lower.include?("@#{id}") || lower.include?("/skill:#{id}")
        return 'explicit:name' if name && (lower.include?("$#{name}") || lower.include?("@#{name}"))

        nil
      end

      # 方法功能：安全地匹配正则表达式模式
      # 参数：pattern - 正则表达式模式字符串
      #       prompt - 待匹配的文本
      # 返回值：Boolean - 匹配成功返回 true，否则返回 false
      def safe_pattern_matches(pattern, prompt)
        Regexp.new(pattern, Regexp::IGNORECASE).match?(prompt)
      rescue StandardError
        false
      end

      # 方法功能：从文件路径和提示词中提取文件类型
      # 参数：paths - 文件路径列表
      #       prompt - 用户提示词
      # 返回值：Set<String> - 文件类型集合（如 ".rb"、".js"）
      def self.file_types_from(paths, prompt)
        out = Set.new
        paths.each do |file_path|
          ext = ::File.extname(file_path)
          out.add(normalize_file_type(ext)) unless ext.empty?
        end
        prompt.scan(/\.[a-z0-9]+/i) do |match|
          out.add(normalize_file_type(match[0]))
        end
        out
      end

      # 方法功能：标准化文件类型格式
      # 参数：value - 原始文件类型（如 "rb" 或 ".rb"）
      # 返回值：String - 标准化后的文件类型（如 ".rb"）
      def self.normalize_file_type(value)
        trimmed = value.strip.downcase
        trimmed.start_with?('.') ? trimmed : ".#{trimmed}"
      end

      # 方法功能：提取 Markdown 文本的第一个段落
      # 参数：markdown - Markdown 文本
      # 返回值：String 或 nil - 第一个非空段落文本
      def self.first_markdown_paragraph(markdown)
        markdown.split(/\n{2,}/).each do |block|
          cleaned = block.sub(/^#+\s*/, '').strip
          return cleaned unless cleaned.empty?
        end
        nil
      end

      # 方法功能：将字符串转换为 URL 友好的 slug 格式
      # 参数：value - 原始字符串
      # 返回值：String - slug 格式的字符串（小写、连字符分隔）
      def self.slug(value)
        result = value.strip.downcase.gsub(/[^a-z0-9_-]+/, '-').gsub(/^-+|-+$/, '')
        result.empty? ? 'skill' : result
      end

      # 方法功能：安全地获取错误消息
      # 参数：error - 异常对象
      # 返回值：String - 错误消息文本
      def self.error_message(error)
        error.message
      rescue StandardError
        error.to_s
      end
    end
  end
end
