# frozen_string_literal: true

# 文件用途：创建计划文件的工具
# 使用方法：通过 create 方法创建 create_plan 工具定义，用于创建或更新 GUI 拥有的实现计划

require 'digest'
require 'fileutils'

module DeepForge
  module Adapters
    module Tool
      # 模块功能：提供 create_plan 工具，用于创建和管理 GUI 计划文件
      module CreatePlanTool
        # 工具名称常量
        CREATE_PLAN_TOOL_NAME = 'create_plan'
        # GUI 计划文件的相对目录
        GUI_PLAN_RELATIVE_DIR = '.dfsdd/plan'

        # 创建计划工具的适配器选项结构体
        CreatePlanAdapterOptions = Struct.new(
          :default_workspace_root,
          :resolve_workspace_root,
          :list_plan_files,
          :write_plan,
          keyword_init: true
        )

        # 方法功能：创建 create_plan 工具定义
        # 参数：options - 适配器选项（可选）
        # 返回值：包含工具定义的哈希
        def self.create(options = {})
          options ||= CreatePlanAdapterOptions.new

          {
            name: CREATE_PLAN_TOOL_NAME,
            description: 'Create or replace a GUI-owned implementation plan.',
            tool_kind: 'file_change',
            input_schema: {
              type: 'object',
              properties: {
                markdown: { type: 'string', description: 'Complete Markdown plan content to save.' },
                source_request: { type: 'string', description: 'Original user request that this plan answers.' },
                title: { type: 'string', description: 'Short display title for the plan.' },
                operation: { type: 'string', enum: %w[draft refine],
                             description: 'Use "draft" for a new plan, "refine" when revising an existing one.' },
                plan_id: { type: 'string', description: 'Optional reserved plan id.' },
                plan_relative_path: { type: 'string', description: 'Optional reserved relative path.' }
              },
              required: %w[markdown operation],
              additional_properties: false
            },
            policy: 'auto',
            should_advertise: ->(context) { plan_tool_context_active?(context) },
            execute: ->(args, context) { execute_create_plan(args, context, options) }
          }
        end

        # 方法功能：检查计划工具上下文是否激活
        # 参数：context - 上下文哈希
        # 返回值：布尔值
        def self.plan_tool_context_active?(context)
          return false unless context

          context[:gui_plan] || context[:thread_mode] == 'plan'
        end

        # 方法功能：执行创建计划操作
        # 参数：args - 参数哈希，context - 上下文，options - 选项
        # 返回值：包含计划信息的哈希
        def self.execute_create_plan(args, context, options)
          unless plan_tool_context_active?(context)
            return error_output('create_plan requires Plan mode or an active GUI plan context')
          end

          input = {
            markdown: args[:markdown].is_a?(String) ? args[:markdown] : nil,
            source_request: args[:source_request].is_a?(String) ? args[:source_request] : nil,
            title: args[:title].is_a?(String) ? args[:title] : nil,
            operation: %w[draft refine].include?(args[:operation]) ? args[:operation] : nil,
            plan_id: args[:plan_id].is_a?(String) ? args[:plan_id] : nil,
            plan_relative_path: args[:plan_relative_path].is_a?(String) ? args[:plan_relative_path] : nil
          }

          return error_output('operation must be "draft" or "refine"') unless input[:operation]

          if input[:markdown].nil? || input[:markdown].strip.empty?
            return error_output('markdown is required and must be non-empty')
          end

          resolved = if context[:gui_plan]
                       resolve_reserved_target(input, context)
                     else
                       resolve_free_form_target(input, context, options)
                     end

          return error_output(resolved[:error]) if resolved[:error]

          workspace_root = if options&.resolve_workspace_root
                             options.resolve_workspace_root.call(resolved[:workspace_root])
                           else
                             resolved[:workspace_root]
                           end

          absolute_path = if File.absolute_path?(workspace_root)
                            File.join(workspace_root, resolved[:relative_path])
                          else
                            File.join(plan_directory(workspace_root), File.basename(resolved[:relative_path]))
                          end

          begin
            assert_within_workspace(absolute_path, workspace_root)
          rescue StandardError => e
            return error_output(e.message)
          end

          return error_output('plan write aborted') if context[:abort_signal]&.aborted?

          writer = options&.write_plan || method(:default_write_plan)
          fingerprint = compute_content_fingerprint(input[:markdown])

          begin
            written = writer.call({
                                    workspace_root: workspace_root,
                                    relative_path: resolved[:relative_path],
                                    absolute_path: absolute_path,
                                    markdown: input[:markdown]
                                  }, context[:abort_signal])
          rescue StandardError => e
            return error_output("plan write failed: #{e.message}")
          end

          return error_output('plan write aborted') if context[:abort_signal]&.aborted?

          {
            output: {
              summary: "#{resolved[:operation] == 'refine' ? 'Refined' : 'Created'} GUI plan at #{resolved[:relative_path]}.",
              plan_id: resolved[:plan_id],
              workspace_root: workspace_root,
              relative_path: resolved[:relative_path],
              absolute_path: written[:path],
              source_request: input[:source_request] || resolved[:source_request],
              title: input[:title] || resolved[:title],
              operation: resolved[:operation],
              saved_at: written[:saved_at],
              content_hash: fingerprint[:hash],
              byte_size: fingerprint[:bytes]
            }
          }
        end

        # 方法功能：解析保留的目标路径
        # 参数：input - 输入参数，context - 上下文
        # 返回值：目标信息哈希或错误哈希
        def self.resolve_reserved_target(input, context)
          context_plan = context[:gui_plan]
          return { error: 'create_plan requires an active GUI plan context' } unless context_plan

          if input[:operation] != context_plan[:operation]
            return { error: 'operation does not match the active GUI plan operation' }
          end

          relative_path = to_relative_path(context_plan[:relative_path])
          unless relative_path && gui_plan_relative_path?(relative_path)
            return { error: 'plan_relative_path must be a direct Markdown file under .dfsdd/plan' }
          end

          if input[:operation] == 'draft' && !gui_plan_current_relative_path?(relative_path)
            return { error: 'legacy .deepseekgui/plan paths can only be refined' }
          end

          if input[:plan_relative_path] && to_relative_path(input[:plan_relative_path]) != context_plan[:relative_path]
            return { error: 'plan_relative_path does not match the reserved GUI plan path' }
          end

          if input[:plan_id] && input[:plan_id] != context_plan[:plan_id]
            return { error: 'plan_id does not match the reserved GUI plan id' }
          end

          workspace_root = context_plan[:workspace_root] || context[:workspace]
          return { error: 'workspace root is required' } unless workspace_root

          {
            workspace_root: workspace_root,
            relative_path: relative_path,
            plan_id: context_plan[:plan_id] || input[:plan_id] || build_gui_plan_id(workspace_root, relative_path),
            operation: input[:operation],
            source_request: context_plan[:source_request],
            title: context_plan[:title]
          }
        end

        # 方法功能：解析自由形式的目标路径
        # 参数：input - 输入参数，context - 上下文，options - 选项
        # 返回值：目标信息哈希或错误哈希
        def self.resolve_free_form_target(input, context, options)
          workspace_root = context[:workspace]&.strip || options&.default_workspace_root&.strip || ''
          return { error: 'workspace root is required' } if workspace_root.empty?

          relative_path = if input[:plan_relative_path]
                            candidate = to_relative_path(input[:plan_relative_path])
                            if candidate.nil? || !gui_plan_current_relative_path?(candidate)
                              return { error: 'plan_relative_path must be a direct Markdown file under .dfsdd/plan' }
                            end

                            candidate
                          else
                            feature_name = derive_feature_name(input[:title] || input[:source_request])
                            existing = list_existing_plan_relative_paths(workspace_root, options)
                            next_available_plan_relative_path(feature_name, existing)
                          end

          {
            workspace_root: workspace_root,
            relative_path: relative_path,
            plan_id: build_gui_plan_id(workspace_root, relative_path),
            operation: input[:operation],
            source_request: input[:source_request],
            title: input[:title]
          }
        end

        # 方法功能：将原始路径转换为相对路径
        # 参数：raw - 原始路径字符串
        # 返回值：规范化后的相对路径
        def self.to_relative_path(raw)
          raw.gsub('\\', '/').sub(%r{^\./}, '').sub(%r{/+$}, '')
        end

        # 方法功能：获取计划文件目录路径
        # 参数：workspace_root - 工作区根目录
        # 返回值：计划目录的绝对路径
        def self.plan_directory(workspace_root)
          File.join(workspace_root, GUI_PLAN_RELATIVE_DIR)
        end

        # 方法功能：断言路径在工作区内
        # 参数：absolute_path - 绝对路径，workspace_root - 工作区根目录
        # 异常：如果路径逃逸工作区则抛出异常
        def self.assert_within_workspace(absolute_path, workspace_root)
          rel = begin
            Pathname.new(absolute_path).relative_path_from(Pathname.new(workspace_root)).to_s
          rescue ArgumentError
            absolute_path
          end
          raise 'plan write escaped the configured workspace root' if rel.start_with?('..') || File.absolute_path?(rel)
        end

        # 方法功能：计算内容指纹
        # 参数：markdown - Markdown 内容
        # 返回值：包含哈希和字节数的哈希
        def self.compute_content_fingerprint(markdown)
          bytes = markdown.bytesize
          hash = Digest::SHA256.hexdigest(markdown)[0, 16]
          { hash: hash, bytes: bytes }
        end

        # 方法功能：构建临时文件路径
        # 参数：target - 目标文件路径
        # 返回值：临时文件路径字符串
        def self.build_temp_path(target)
          dot = target.rindex('.')
          if dot&.positive?
            base = target[0...dot]
            ext = target[dot..]
          else
            base = target
            ext = ''
          end
          "#{base}.tmp-#{Process.pid}-#{Time.now.to_i}#{ext}"
        end

        # 方法功能：默认的计划文件写入实现
        # 参数：target - 目标信息，signal - 中止信号
        # 返回值：包含路径和保存时间的哈希
        def self.default_write_plan(target, signal)
          raise 'plan write aborted before start' if signal&.aborted?

          FileUtils.mkdir_p(File.dirname(target[:absolute_path]))
          temp_path = build_temp_path(target[:absolute_path])
          File.write(temp_path, target[:markdown])

          raise 'plan write aborted before atomic rename' if signal&.aborted?

          File.rename(temp_path, target[:absolute_path])
          { path: target[:absolute_path], saved_at: Time.now.utc.strftime('%FT%TZ') }
        end

        # 方法功能：列出已存在的计划文件相对路径
        # 参数：workspace_root - 工作区根目录，options - 选项
        # 返回值：相对路径数组
        def self.list_existing_plan_relative_paths(workspace_root, options)
          return options.list_plan_files.call(workspace_root) if options&.list_plan_files

          dir = plan_directory(workspace_root)
          return [] unless File.directory?(dir)

          Dir.entries(dir)
             .select { |name| name.downcase.end_with?('.md') }
             .map { |name| "#{GUI_PLAN_RELATIVE_DIR}/#{name}" }
        rescue StandardError
          []
        end

        # 方法功能：从种子字符串派生功能名称
        # 参数：seed - 种子字符串（标题或请求）
        # 返回值：安全的功能名称字符串
        def self.derive_feature_name(seed)
          raw = (seed || '')
                .unicode_normalize(:nfkc)
                .downcase
                .gsub(/[\x00-\x1F]/, ' ')
                .gsub(%r{[<>:"|?*\\/]+}, ' ')
                .gsub(/[\s_]+/, '-')
                .gsub(/-+/, '-')
                .gsub(/^[.\-\s]+/, '')
                .gsub(/[.\-\s]+$/, '')

          safe = raw[0, 96].gsub(/[.\-\s]+$/, '')
          safe.empty? ? 'plan' : safe
        end

        # 方法功能：构建 GUI 计划 ID
        # 参数：workspace_root - 工作区根目录，relative_path - 相对路径
        # 返回值：计划 ID 字符串
        def self.build_gui_plan_id(workspace_root, relative_path)
          Digest::SHA256.hexdigest("#{workspace_root}/#{relative_path}")[0, 16]
        end

        # 方法功能：检查路径是否为有效的 GUI 计划相对路径
        # 参数：path - 相对路径
        # 返回值：布尔值
        def self.gui_plan_relative_path?(path)
          path.start_with?("#{GUI_PLAN_RELATIVE_DIR}/") && path.end_with?('.md')
        end

        # 方法功能：检查路径是否为当前 GUI 计划相对路径
        # 参数：path - 相对路径
        # 返回值：布尔值
        def self.gui_plan_current_relative_path?(path)
          gui_plan_relative_path?(path)
        end

        # 方法功能：获取下一个可用的计划相对路径
        # 参数：feature_name - 功能名称，existing - 已存在的路径数组
        # 返回值：可用的相对路径字符串
        def self.next_available_plan_relative_path(feature_name, existing)
          candidate = "#{GUI_PLAN_RELATIVE_DIR}/#{feature_name}.md"
          return candidate unless existing.include?(candidate)

          (2..1000).each do |i|
            numbered = "#{GUI_PLAN_RELATIVE_DIR}/#{feature_name}-#{i}.md"
            return numbered unless existing.include?(numbered)
          end

          "#{GUI_PLAN_RELATIVE_DIR}/#{feature_name}-#{Time.now.to_i}.md"
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
