# frozen_string_literal: true

require_relative 'lib/deepforge'

Gem::Specification.new do |spec|
  spec.name          = 'deepforge'
  spec.version       = DeepForge::VERSION
  spec.authors       = ['zbin.song@gmail.com']
  spec.summary       = 'DeepForge Agent Runtime'
  spec.description   = 'Local HTTP/SSE agent runtime for AI GUI applications'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.2.0'

  spec.files         = Dir['lib/**/*.rb', 'config.ru', '*.gemspec']
  spec.require_paths = ['lib']

  spec.add_dependency 'falcon', '~> 0.50'
  spec.add_dependency 'json'
  spec.add_dependency 'listen'
  spec.add_dependency 'rack', '~> 3.1'
  spec.add_dependency 'roda', '~> 3.80'
  spec.add_dependency 'sqlite3'

  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rspec-mocks', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.60'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
