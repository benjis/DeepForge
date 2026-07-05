# frozen_string_literal: true

# 文件用途：工作区检查器端口，提供检查线程本地工作区状态的功能
# 使用方法：继承此类并实现status方法，默认实现读取git状态

module DeepForge
  module Ports
    # @abstract Subclass and implement {#status}
    # Port for inspecting the local workspace of a thread. The default
    # implementation reads git status when available and reports `nil`
    # fields when the workspace is not a git repository.

    # 类功能：工作区检查器基类，定义工作区状态检查接口
    class WorkspaceInspector
      # 方法功能：获取工作区状态
      # 参数：workspace - 工作区路径
      # 返回值：工作区状态对象
      # 使用方法：传入工作区路径，返回包含git状态等信息的对象
      # @param workspace [String]
      # @return [Contracts::WorkspaceStatus]
      def status(workspace)
        raise NotImplementedError
      end
    end
  end
end
