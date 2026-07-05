# frozen_string_literal: true

# 文件用途：Git 代码审查目标解析模块
# 使用方法：将审查目标（未提交更改、基准分支、特定提交等）解析为标题和提示词对，
#           用于驱动代码审查流程。

require 'open3'
require 'etc'
require 'tmpdir'
require_relative '../contracts/review'

module DeepForge
  module Review
    # 默认最大差异字节数
    DEFAULT_DIFF_MAX_BYTES = 256 * 1024
    # Git 命令超时时间（秒）
    GIT_COMMAND_TIMEOUT = 10
    # Git 命令最大输出缓冲区
    GIT_COMMAND_MAX_BUFFER = 384 * 1024

    # 解析后的审查提示词结构体
    ResolvedReviewPrompt = Struct.new(:title, :prompt, keyword_init: true)

    # 审查目标解析选项结构体
    ResolveReviewTargetOptions = Struct.new(:target, :workspace, :max_diff_bytes, keyword_init: true)

    # 方法功能：将审查目标解析为标题和提示词对
    # 参数：options - ResolveReviewTargetOptions 结构体
    # 返回值：ResolvedReviewPrompt - 包含标题和提示词的对象
    # 异常：RuntimeError - 如果工作区不是有效的 git 仓库
    def self.resolve_review_target_prompt(options)
      workspace = normalize_workspace(options.workspace)
      max_diff_bytes = options.max_diff_bytes || DEFAULT_DIFF_MAX_BYTES

      if options.target.kind == Contracts::ReviewTargetKind::CUSTOM
        return ResolvedReviewPrompt.new(
          title: 'Custom code review',
          prompt: build_prompt(
            workspace: workspace,
            title: 'Custom code review',
            body: "The user supplied custom review instructions.\n\n<custom_instructions>\n#{options.target.instructions}\n</custom_instructions>",
            max_diff_bytes: max_diff_bytes
          )
        )
      end

      assert_git_workspace(workspace)

      case options.target.kind
      when Contracts::ReviewTargetKind::UNCOMMITTED_CHANGES
        resolve_uncommitted_changes(workspace, max_diff_bytes)
      when Contracts::ReviewTargetKind::BASE_BRANCH
        resolve_base_branch(workspace, options.target.branch, max_diff_bytes)
      when Contracts::ReviewTargetKind::COMMIT
        resolve_commit(workspace, options.target.sha, max_diff_bytes)
      else
        raise ArgumentError, "unknown review target kind: #{options.target.kind}"
      end
    end

    class << self
      private

      # 方法功能：解析未提交的更改作为审查目标
      # 参数：workspace - 工作区路径
      #       max_diff_bytes - 最大差异字节数
      # 返回值：ResolvedReviewPrompt - 包含标题和提示词的对象
      def resolve_uncommitted_changes(workspace, max_diff_bytes)
        status_out, = run_git(workspace, %w[status --short])
        staged_out, = run_git(workspace, %w[diff --cached --stat --patch --find-renames])
        unstaged_out, = run_git(workspace, %w[diff --stat --patch --find-renames])
        untracked_out, = run_git(workspace, %w[ls-files --others --exclude-standard])

        body = [
          'Review the current code changes, including staged, unstaged, and untracked files.',
          '',
          '<git_status_short>',
          status_out || '(clean)',
          '</git_status_short>',
          '',
          '<staged_diff>',
          staged_out || '(no staged diff)',
          '</staged_diff>',
          '',
          '<unstaged_diff>',
          unstaged_out || '(no unstaged diff)',
          '</unstaged_diff>',
          '',
          '<untracked_files>',
          untracked_out || '(no untracked files)',
          '</untracked_files>'
        ].join("\n")

        ResolvedReviewPrompt.new(
          title: 'Review current changes',
          prompt: build_prompt(workspace: workspace, title: 'Review current changes', body: body,
                               max_diff_bytes: max_diff_bytes)
        )
      end

      # 方法功能：解析基准分支作为审查目标
      # 参数：workspace - 工作区路径
      #       branch - 基准分支名称
      #       max_diff_bytes - 最大差异字节数
      # 返回值：ResolvedReviewPrompt - 包含标题和提示词的对象
      def resolve_base_branch(workspace, branch, max_diff_bytes)
        normalized_branch = branch.strip
        raise ArgumentError, 'base branch is required' if normalized_branch.empty?

        merge_base_out, = run_git(workspace, ['merge-base', 'HEAD', normalized_branch])
        merge_base = merge_base_out.strip
        raise ArgumentError, "could not resolve merge-base with #{normalized_branch}" if merge_base.empty?

        diff_out, = run_git(workspace, ['diff', '--stat', '--patch', '--find-renames', merge_base])

        body = [
          "Review the code changes from merge-base #{merge_base} against branch #{normalized_branch}.",
          '',
          '<git_diff>',
          diff_out || '(no diff)',
          '</git_diff>'
        ].join("\n")

        ResolvedReviewPrompt.new(
          title: "Review changes against #{normalized_branch}",
          prompt: build_prompt(workspace: workspace, title: "Review changes against #{normalized_branch}", body: body,
                               max_diff_bytes: max_diff_bytes)
        )
      end

      # 方法功能：解析特定提交作为审查目标
      # 参数：workspace - 工作区路径
      #       sha - 提交的 SHA 值
      #       max_diff_bytes - 最大差异字节数
      # 返回值：ResolvedReviewPrompt - 包含标题和提示词的对象
      def resolve_commit(workspace, sha, max_diff_bytes)
        normalized_sha = sha.strip
        raise ArgumentError, 'commit sha is required' if normalized_sha.empty?

        show_out, = run_git(workspace, [
                              'show', '--stat', '--patch', '--find-renames', '--format=fuller', normalized_sha
                            ])

        body = [
          "Review commit #{normalized_sha}.",
          '',
          '<git_show>',
          show_out || '(no commit output)',
          '</git_show>'
        ].join("\n")

        ResolvedReviewPrompt.new(
          title: "Review commit #{normalized_sha[0, 12]}",
          prompt: build_prompt(workspace: workspace, title: "Review commit #{normalized_sha}", body: body,
                               max_diff_bytes: max_diff_bytes)
        )
      end

      # 方法功能：验证工作区是否为有效的 git 仓库
      # 参数：workspace - 工作区路径
      # 返回值：Boolean - 验证通过返回 true
      def assert_git_workspace(workspace)
        _out, = run_git(workspace, %w[rev-parse --show-toplevel])
        # run_git raises on failure, so we just need to survive here
        true
      end

      # 方法功能：执行 git 命令并返回输出
      # 参数：cwd - 工作目录
      #       args - git 命令参数数组
      # 返回值：Array<String> - [stdout, stderr] 输出数组
      # 异常：RuntimeError - 如果 git 命令执行失败
      def run_git(cwd, args)
        stdout_str = nil
        stderr_str = nil

        Open3.popen3('git', *args, chdir: cwd, timeout: GIT_COMMAND_TIMEOUT) do |_stdin, stdout, stderr, wait_thr|
          stdout_str = stdout.read
          stderr_str = stderr.read
          wait_thr.join
          status = wait_thr.value
          unless status.success?
            msg = stderr_str&.strip || stdout_str&.strip || status.to_s
            raise "git #{args.join(' ')} failed: #{msg}"
          end
        end

        [stdout_str&.rstrip, stderr_str&.rstrip]
      end

      # 方法功能：构建审查提示词
      # 参数：workspace - 工作区路径
      #       title - 审查标题
      #       body - 审查内容
      #       max_diff_bytes - 最大差异字节数
      # 返回值：String - 构建后的审查提示词
      def build_prompt(workspace:, title:, body:, max_diff_bytes:)
        raw = [
          title,
          '',
          "Workspace: #{workspace}",
          '',
          body,
          '',
          'Review instructions:',
          '- Inspect the supplied diff and use read-only tools if you need more context.',
          '- Report only concrete bugs introduced by the reviewed change.',
          '- Return the strict JSON shape required by the system prompt.'
        ].join("\n")

        truncate_utf8(raw, max_diff_bytes)
      end

      # 方法功能：标准化工作区路径
      # 参数：workspace - 原始工作区路径
      # 返回值：String - 标准化后的路径（处理 ~ 和空值）
      def normalize_workspace(workspace)
        trimmed = workspace.strip
        return Etc.getlogin ? Dir.home : Dir.pwd if trimmed.empty? || trimmed == '~'

        if trimmed.start_with?('~/')
          File.join(Dir.home, trimmed[2..])
        else
          trimmed
        end
      end

      # 方法功能：将文本截断到指定字节数（保持 UTF-8 完整性）
      # 参数：text - 原始文本
      #       max_bytes - 最大字节数
      # 返回值：String - 截断后的文本
      def truncate_utf8(text, max_bytes)
        bytes = text.encode('UTF-8')
        return text if bytes.bytesize <= max_bytes

        truncated = bytes.byteslice(0, max_bytes)
        # Attempt to decode without splitting a multi-byte character
        if truncated.bytes.last(1).first >= 0x80
          truncated = truncated[0...-truncated.bytes.last(3).count do |b|
            b >= 0x80
          end]
        end
        "#{truncated}\n\n[Review input truncated to #{max_bytes} bytes. Use read-only tools to inspect omitted context.]"
      end
    end
  end
end
