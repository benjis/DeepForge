# frozen_string_literal: true

module DeepForge
  module Server
    JsonResponse = Struct.new(:status, :headers, :body, keyword_init: true)

    def self.json_response(body, status = 200)
      JsonResponse.new(
        status: status,
        headers: { 'content-type' => 'application/json; charset=utf-8' },
        body: JSON.generate(body)
      )
    end
  end
end
