# frozen_string_literal: true

# 文件用途：本地工作区检查器
# 通过调用 git 命令检查工作区状态，包括分支、HEAD SHA、是否脏等信息
# 仅读取工作区状态，不会修改工作区
# 使用方法：LocalWorkspaceInspector.new.status('/path/to/workspace')

require 'open3'
require 'pathname'
require 'time'

require_relative '../../ports/workspace_inspector'
require_relative '../../contracts/workspace'

module DeepForge
  module Adapters
    module Workspace
      # 类功能：本地工作区检查器
      # 继承自 WorkspaceInspector 接口，通过 git 命令获取工作区状态
      class LocalWorkspaceInspector < DeepForge::Ports::WorkspaceInspector
        # 方法功能：初始化本地工作区检查器
        # 参数：exec_fn - 可选的命令执行函数，用于测试或自定义执行方式
        # 返回值：LocalWorkspaceInspector 实例
        def initialize(exec_fn: nil)
          @exec_fn = exec_fn || method(:default_exec)
        end

        # 方法功能：获取工作区状态
        # 检查工作区是否存在、是否为 git 仓库，以及分支、HEAD SHA、文件变更数量等信息
        # 参数：workspace - 工作区路径
        # 返回值：DeepForge::Contracts::WorkspaceStatus 对象，包含工作区状态信息
        def status(workspace)
          abs = File.expand_path(workspace)
          exists = File.exist?(abs)

          unless exists
            return DeepForge::Contracts::WorkspaceStatus.new(
              path: abs,
              exists: false,
              is_git_repository: false,
              branch: nil,
              head_sha: nil,
              is_dirty: nil,
              file_change_count: nil,
              checked_at: Time.now.utc.strftime('%FT%TZ')
            )
          end

          inside = inside_git_repository?(abs)
          unless inside
            return DeepForge::Contracts::WorkspaceStatus.new(
              path: abs,
              exists: true,
              is_git_repository: false,
              branch: nil,
              head_sha: nil,
              is_dirty: nil,
              file_change_count: nil,
              checked_at: Time.now.utc.strftime('%FT%TZ')
            )
          end

          branch = run_git(abs, ['rev-parse', '--abbrev-ref', 'HEAD'])
          head_sha = run_git(abs, %w[rev-parse HEAD])
          status_output = run_git(abs, ['status', '--porcelain'])
          file_change_count = status_output ? status_output.split("\n").reject(&:empty?).length : 0
          is_dirty = file_change_count.positive?

          DeepForge::Contracts::WorkspaceStatus.new(
            path: abs,
            exists: true,
            is_git_repository: true,
            branch: branch,
            head_sha: head_sha,
            is_dirty: is_dirty,
            file_change_count: file_change_count,
            checked_at: Time.now.utc.strftime('%FT%TZ')
          )
        end

        private

        # 方法功能：检查目录是否在 git 仓库内
        # 调用 git rev-parse --is-inside-work-tree 命令
        # 参数：workspace - 工作区路径
        # 返回值：在 git 仓库内返回 true，否则返回 false
        def inside_git_repository?(workspace)
          result = run_git(workspace, ['rev-parse', '--is-inside-work-tree'])
          result == 'true'
        end

        # 方法功能：执行 git 命令
        # 使用指定的执行函数运行 git 命令并返回输出
        # 参数：cwd - 工作目录，args - git 命令参数
        # 返回值：命令输出字符串，执行失败则返回 nil
        def run_git(cwd, args)
          stdout, _status = @exec_fn.call('git', args, chdir: cwd)
          stdout.strip
        rescue StandardError
          nil
        end

        # 方法功能：默认的命令执行函数
        # 使用 Open3.capture2 执行外部命令
        # 参数：file - 可执行文件路径，args - 命令参数，chdir - 工作目录
        # 返回值：标准输出和状态的元组
        def default_exec(file, args, chdir:)
          Open3.capture2(file, *args, chdir: chdir)
        end
      end
    end
  end
end
