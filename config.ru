# frozen_string_literal: true

require_relative 'lib/deepforge/server/app'

# Rack config file for Falcon
# Runtime is injected at startup via DeepForge::App.runtime=
run DeepForge::App
