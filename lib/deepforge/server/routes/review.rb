# frozen_string_literal: true

# 文件用途：代码审查路由模块，处理代码审查请求和执行
# 使用方法：通过 POST /v1/threads/:id/review 端点启动代码审查

require 'json'
require_relative '../response'
require_relative 'runtime_error'

module DeepForge
  module Server
    module Routes
      # 代码审查端点处理模块，提供代码审查的启动和管理功能
      module Review
        # 启动代码审查
        # @param turns [DialogueTurnService] 轮次服务实例
        # @param thread_id [String] 线程 ID
        # @param request [Hash] 请求对象，包含 :body
        # @param on_started [Proc, nil] 审查开始时的回调函数
        # @return [JsonResponse] 已启动的审查响应
        def self.start_review(turns, thread_id, request, on_started: nil)
          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          unless body.value.is_a?(Hash) && body.value['target'].is_a?(Hash)
            return DeepForge::Server::Routes::ERRORS[:validation].call('target is required and must be an object')
          end

          target = body.value['target']

          unless target['kind'].is_a?(String) && !target['kind'].empty?
            return DeepForge::Server::Routes::ERRORS[:validation].call('target.kind is required')
          end

          unless %w[uncommittedChanges baseBranch commit custom].include?(target['kind'])
            return DeepForge::Server::Routes::ERRORS[:validation].call('target.kind must be one of: uncommittedChanges, baseBranch, commit, custom')
          end

          if target['kind'] == 'baseBranch' && (!target['branch'].is_a?(String) || target['branch'].empty?)
            return DeepForge::Server::Routes::ERRORS[:validation].call('target.branch is required for baseBranch review')
          end

          if target['kind'] == 'commit' && (!target['sha'].is_a?(String) || target['sha'].empty?)
            return DeepForge::Server::Routes::ERRORS[:validation].call('target.sha is required for commit review')
          end

          if target['kind'] == 'custom' && (!target['instructions'].is_a?(String) || target['instructions'].empty?)
            return DeepForge::Server::Routes::ERRORS[:validation].call('target.instructions is required for custom review')
          end

          if body.value['model'] && (!body.value['model'].is_a?(String) || body.value['model'].empty?)
            return DeepForge::Server::Routes::ERRORS[:validation].call('model must be a non-empty string')
          end

          title = review_target_title(target)

          begin
            started = turns.start_turn(
              threadId: thread_id,
              request: {
                prompt: review_target_prompt(target),
                displayText: title,
                model: body.value['model'],
                mode: 'agent'
              }
            )

            review_item_id = "item_#{started[:turn_id]}_review"
            turns.apply_item(
              thread_id,
              make_review_item(
                id: review_item_id,
                threadId: thread_id,
                turnId: started[:turn_id],
                target: target,
                title: title,
                status: 'running'
              )
            )

            response = started.merge(reviewItemId: review_item_id)
            on_started&.call(response, target, body.value['model'])
            DeepForge::Server.json_response(response, 202)
          rescue StandardError => e
            raise unless e.message.match?(/not found/i)

            DeepForge::Server::Routes::ERRORS[:not_found].call(e.message)
          end
        end

        # 获取审查目标的标题
        # @param target [String] 审查目标类型
        # @return [String] 审查标题
        def self.review_target_title(target)
          case target
          when 'code'
            'Code Review'
          when 'plan'
            'Plan Review'
          when 'security'
            'Security Review'
          else
            'Review'
          end
        end

        # 获取审查目标的提示词
        # @param target [String] 审查目标类型
        # @return [String] 审查提示词
        def self.review_target_prompt(target)
          case target
          when 'code'
            'Review the code for issues, improvements, and best practices.'
          when 'plan'
            'Review the plan for completeness and feasibility.'
          when 'security'
            'Review for security vulnerabilities and concerns.'
          else
            'Perform a review.'
          end
        end

        # 创建审查项目
        # @param id [String] 项目 ID
        # @param thread_id [String] 线程 ID
        # @param turn_id [String] 轮次 ID
        # @param target [String] 审查目标
        # @param title [String] 审查标题
        # @param status [String] 项目状态
        # @return [Hash] 审查项目
        def self.make_review_item(id:, threadId:, turnId:, target:, title:, status:)
          {
            id: id,
            threadId: threadId,
            turnId: turnId,
            kind: 'review',
            target: target,
            title: title,
            status: status
          }
        end
      end
    end
  end
end
