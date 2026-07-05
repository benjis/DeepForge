# frozen_string_literal: true

# 文件用途：定义内存系统的请求、响应和数据结构
# 使用方法：用于内存的创建、更新、查询和诊断

module DeepForge
  module Contracts
    # 内存作用域常量：定义内存的存储级别
    module MemoryScope
      USER = 'user'
      WORKSPACE = 'workspace'
      PROJECT = 'project'
    end

    # 内存记录：存储一条内存的完整信息
    MemoryRecord = Struct.new(
      :id,
      :content,
      :scope,
      :workspace,
      :project,
      :source_thread_id,
      :source_turn_id,
      :tags,
      :confidence,
      :created_at,
      :updated_at,
      :disabled_at,
      :deleted_at,
      keyword_init: true
    )

    # 内存创建请求：提交新内存记录时使用
    MemoryCreateRequest = Struct.new(
      :content,
      :scope,
      :workspace,
      :project,
      :source_thread_id,
      :source_turn_id,
      :tags,
      :confidence,
      keyword_init: true
    )

    # 内存更新请求：更新已有内存记录时使用
    MemoryUpdateRequest = Struct.new(
      :content,
      :tags,
      :confidence,
      :disabled,
      keyword_init: true
    )

    # 内存诊断信息：用于调试，返回内存存储的统计信息
    MemoryDiagnostics = Struct.new(
      :enabled,
      :root_dir,
      :active_count,
      :tombstone_count,
      :last_injected_ids,
      keyword_init: true
    )
  end
end
