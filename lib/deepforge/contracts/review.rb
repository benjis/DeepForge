# frozen_string_literal: true

# 文件用途：定义代码审查相关的请求、响应和数据结构
# 使用方法：用于发起代码审查、定位审查发现和生成审查报告

module DeepForge
  module Contracts
    # 行范围：指定代码审查的起止行号
    ReviewLineRange = Struct.new(
      :start,
      :end,
      keyword_init: true
    )

    # 代码位置：指定审查发现所在的文件路径和行范围
    ReviewCodeLocation = Struct.new(
      :absolute_file_path,
      :line_range,
      keyword_init: true
    )

    # 审查发现：包含标题、内容、置信度和优先级
    ReviewFinding = Struct.new(
      :title,
      :body,
      :confidence_score,
      :priority,
      :code_location,
      keyword_init: true
    )

    # 审查输出：包含所有发现和总体评价
    ReviewOutput = Struct.new(
      :findings,
      :overall_correctness,
      :overall_explanation,
      :overall_confidence_score,
      keyword_init: true
    )

    # 审查目标类型常量：定义审查的目标范围
    module ReviewTargetKind
      UNCOMMITTED_CHANGES = 'uncommittedChanges'
      BASE_BRANCH = 'baseBranch'
      COMMIT = 'commit'
      CUSTOM = 'custom'
    end

    # 审查目标：指定审查的类型、分支、提交和自定义指令
    ReviewTarget = Struct.new(
      :kind,
      :branch,
      :sha,
      :instructions,
      keyword_init: true
    )

    # 开始审查请求：发起代码审查时使用
    StartReviewRequest = Struct.new(
      :target,
      :model,
      keyword_init: true
    )

    # 开始审查响应：返回审查任务的线程ID和项目ID
    StartReviewResponse = Struct.new(
      :thread_id,
      :turn_id,
      :user_message_item_id,
      :review_item_id,
      keyword_init: true
    )

    # 根据审查目标类型生成可读的标题
    def self.review_target_title(target)
      case target.kind
      when ReviewTargetKind::UNCOMMITTED_CHANGES
        'Review current changes'
      when ReviewTargetKind::BASE_BRANCH
        "Review changes against #{target.branch}"
      when ReviewTargetKind::COMMIT
        "Review commit #{target.sha[0, 12]}"
      when ReviewTargetKind::CUSTOM
        'Custom code review'
      end
    end

    # 根据审查目标类型生成审查命令提示
    def self.review_target_prompt(target)
      case target.kind
      when ReviewTargetKind::UNCOMMITTED_CHANGES
        '/review'
      when ReviewTargetKind::BASE_BRANCH
        "/review base #{target.branch}"
      when ReviewTargetKind::COMMIT
        "/review commit #{target.sha}"
      when ReviewTargetKind::CUSTOM
        "/review #{target.instructions}"
      end
    end
  end
end
