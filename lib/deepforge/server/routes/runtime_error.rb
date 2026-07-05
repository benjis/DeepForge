# frozen_string_literal: true

require_relative '../response'

module DeepForge
  module Server
    module Routes
      RuntimeError_ = Struct.new(:code, :message, :details, keyword_init: true)

      def self.error_response(body, status)
        DeepForge::Server.json_response(body, status)
      end

      ERRORS = {
        unauthorized: lambda { |message = 'unauthorized'|
          error_response({ code: 'unauthorized', message: message }, 401)
        },
        forbidden: lambda { |message = 'forbidden'|
          error_response({ code: 'forbidden', message: message }, 403)
        },
        not_found: lambda { |message = 'not found'|
          error_response({ code: 'not_found', message: message }, 404)
        },
        validation: lambda { |message, issues = nil|
          body = { code: 'validation_error', message: message }
          body[:details] = issues if issues
          error_response(body, 400)
        },
        attachment_validation: lambda { |message, issues = nil|
          body = { code: 'attachment_validation_failed', message: message }
          body[:details] = issues if issues
          error_response(body, 400)
        },
        conflict: lambda { |message|
          error_response({ code: 'conflict', message: message }, 409)
        },
        not_implemented: lambda { |message|
          error_response({ code: 'not_implemented', message: message }, 501)
        },
        unavailable: lambda { |message|
          error_response({ code: 'capability_unavailable', message: message }, 503)
        },
        internal: lambda { |message|
          error_response({ code: 'internal_error', message: message }, 500)
        }
      }.freeze
    end
  end
end
