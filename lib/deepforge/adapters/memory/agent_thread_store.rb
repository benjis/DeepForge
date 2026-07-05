# frozen_string_literal: true

# 文件用途：基于内存的线程存储器
# 使用方法：用于测试环境。提供线程的增删改查操作。文件系统持久化实现在此基础上扩展。

module DeepForge
  module Adapters
    module Memory
      # 基于内存的线程存储器，用于测试环境。文件系统持久化实现在此基础上扩展。
      class AgentThreadStore
        def initialize
          # 存储所有线程的哈希表，键为线程 ID
          @threads = {}
        end

        # 列出所有线程，按更新时间倒序排列
        # 参数：options - 可选的过滤选项哈希
        # 返回值：Array<Hash>，线程摘要列表
        def list(_options = {})
          @threads.values
                  .map { |t| to_thread_summary(t) }
                  .sort_by { |t| -t[:updated_at].to_i }
        end

        # 根据 ID 获取线程详情
        # 参数：thread_id - 线程 ID
        # 返回值：Hash 或 nil，线程完整记录
        def get(thread_id)
          @threads[thread_id]
        end

        # 插入或更新线程记录
        # 参数：thread - 线程哈希，必须包含 :id 键
        # 返回值：Hash，保存后的线程记录
        def upsert(thread)
          @threads[thread[:id]] = thread
          thread
        end

        # 删除指定线程
        # 参数：thread_id - 线程 ID
        # 返回值：Boolean，是否成功删除
        def delete(thread_id)
          @threads.delete(thread_id) ? true : false
        end

        private

        # 将完整线程记录转换为摘要格式（内部方法）
        # 参数：thread - 完整线程记录
        # 返回值：Hash，线程摘要
        def to_thread_summary(thread)
          {
            id: thread[:id],
            title: thread[:title],
            workspace: thread[:workspace],
            model: thread[:model],
            mode: thread[:mode],
            status: thread[:status],
            relation: thread[:relation],
            parent_thread_id: thread[:parent_thread_id],
            forked_from_thread_id: thread[:forked_from_thread_id],
            forked_from_title: thread[:forked_from_title],
            created_at: thread[:created_at],
            updated_at: thread[:updated_at]
          }
        end
      end
    end
  end
end
