# frozen_string_literal: true

require 'falcon'
require 'async/http/endpoint'
require 'json'
require 'socket'
require_relative 'app'

module DeepForge
  module Server
    NodeHttpServerHandle = Struct.new(:server, :host, :port, :thread, keyword_init: true)

    def self.start_node_http_server(app: nil, host: '127.0.0.1', port: 8899)
      rack_app = app || DeepForge::App

      server = Falcon::Server.new(
        Falcon::Server.middleware(rack_app),
        Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
      )

      server_thread = Thread.new do
        Async { server.run }
      end

      wait_for_server(host, port)

      $stdout.puts "DEEPFORGE_READY #{JSON.generate(service: 'deepforge', mode: 'serve', port: port)}"
      $stdout.flush

      NodeHttpServerHandle.new(
        server: server,
        host: host,
        port: port,
        thread: server_thread
      )
    end

    private_class_method def self.wait_for_server(host, port, timeout = 30)
      start = Time.now
      loop do
        TCPSocket.new(host, port).close
        return
      rescue Errno::ECONNREFUSED
        raise "Server failed to start within #{timeout}s" if Time.now - start > timeout

        sleep 0.1
      end
    end
  end
end

module DeepForge
  module Server
    class NodeHttpServerHandle
      def close
        @server&.stop if @server.respond_to?(:stop)
      end
    end
  end
end
