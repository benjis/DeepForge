# frozen_string_literal: true

# 文件用途：附件路由模块，处理文件附件的上传、获取和诊断
# 使用方法：通过 POST /v1/attachments 上传附件，GET /v1/attachments/:id 获取元数据

require 'json'
require 'base64'
require_relative '../response'
require_relative 'runtime_error'

module DeepForge
  module Server
    module Routes
      # 附件端点处理模块，提供附件的 CRUD 操作
      module Attachments
        # 上传附件
        # @param store [AttachmentStore, nil] 附件存储实例
        # @param request [Hash] 请求对象，包含 :body
        # @return [JsonResponse] 上传的附件信息
        def self.upload_attachment(store, request)
          return DeepForge::Server::Routes::ERRORS[:unavailable].call('attachment store is unavailable') unless store

          body = DeepForge::Server.read_json_body(request[:body])
          return body.response unless body.ok

          unless body.value.is_a?(Hash)
            return DeepForge::Server::Routes::ERRORS[:attachment_validation].call('invalid attachment upload body')
          end

          unless body.value['name'].is_a?(String) && !body.value['name'].empty?
            return DeepForge::Server::Routes::ERRORS[:attachment_validation].call('name is required')
          end

          unless body.value['dataBase64'].is_a?(String) && !body.value['dataBase64'].empty?
            return DeepForge::Server::Routes::ERRORS[:attachment_validation].call('dataBase64 is required')
          end

          begin
            attachment = store.create(
              name: body.value['name'],
              mimeType: body.value['mimeType'],
              data: Base64.decode64(body.value['dataBase64']),
              textFallback: body.value['textFallback'],
              threadId: body.value['threadId'],
              workspace: body.value['workspace']
            )
            DeepForge::Server.json_response({ attachment: attachment }, 201)
          rescue StandardError => e
            DeepForge::Server::Routes::ERRORS[:attachment_validation].call(error_message(e))
          end
        end

        # 获取附件元数据
        # @param store [AttachmentStore, nil] 附件存储实例
        # @param id [String] 附件 ID
        # @return [JsonResponse] 附件元数据
        def self.get_attachment_metadata(store, id)
          return DeepForge::Server::Routes::ERRORS[:unavailable].call('attachment store is unavailable') unless store

          attachment = store.get(id)
          return DeepForge::Server::Routes::ERRORS[:not_found].call("attachment not found: #{id}") unless attachment

          DeepForge::Server.json_response({ attachment: attachment })
        end

        # 获取附件内容
        # @param store [AttachmentStore, nil] 附件存储实例
        # @param id [String] 附件 ID
        # @param request [Hash] 请求对象，包含 :url
        # @return [JsonResponse] 附件内容（Base64 编码）
        def self.get_attachment_content(store, id, request)
          return DeepForge::Server::Routes::ERRORS[:unavailable].call('attachment store is unavailable') unless store

          url = URI(request[:url])
          query_params = URI.decode_www_form(url.query || '').to_h

          begin
            attachment = store.resolve_content(id, {
                                                 threadId: query_params['thread_id'],
                                                 workspace: query_params['workspace']
                                               })
            DeepForge::Server.json_response({
                                              attachment: attachment.except(:data),
                                              dataBase64: Base64.encode64(attachment[:data])
                                            })
          rescue StandardError => e
            msg = error_message(e)
            if msg.match?(/not authorized/i)
              DeepForge::Server::Routes::ERRORS[:forbidden].call(msg)
            else
              DeepForge::Server::Routes::ERRORS[:not_found].call(msg)
            end
          end
        end

        # 获取附件诊断信息
        # @param store [AttachmentStore, nil] 附件存储实例
        # @return [JsonResponse] 诊断信息
        def self.attachment_diagnostics(store)
          unless store
            return DeepForge::Server.json_response({
                                                     enabled: false,
                                                     root_dir: '',
                                                     count: 0,
                                                     totalBytes: 0
                                                   })
          end

          DeepForge::Server.json_response(store.diagnostics)
        end

        # 从异常中提取错误消息
        # @param error [Exception] 错误实例
        # @return [String] 错误消息
        def self.error_message(error)
          error.is_a?(Exception) ? error.message : error.to_s
        end
      end
    end
  end
end
