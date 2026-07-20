# frozen_string_literal: true

require_relative "lib/inquirex/version"

Gem::Specification.new do |spec|
  spec.name = "inquirex"
  spec.version = Inquirex::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "A declarative, rules-driven questionnaire engine for building conditionally-branching intake forms, qualification wizards, and surveys in pure Ruby."
  spec.description = "Inquirex lets you define multi-step questionnaires as directed graphs with conditional branching, using a conversational DSL (ask, say, mention) and an AST-based rule system (contains, equals, greater_than, all, any). The engine walks the graph, collects structured answers, and serializes everything to JSON — making it the ideal backbone for cross-platform intake forms where the frontend is a chat widget, a terminal, or a mobile app. Framework-agnostic, no third-party dependencies, thread-safe immutable definitions."
  spec.homepage = "https://github.com/inquirex/inquirex"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = "https://qualified.at"
  spec.metadata["source_code_uri"] = "https://github.com/inquirex/inquirex"
  spec.metadata["changelog_uri"] = "https://github.com/inquirex/inquirex/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Dir-based (not `git ls-files`) so the gemspec evaluates in contexts
  # without git — e.g. vendored as a path gem inside a slim Docker image.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob("{lib,exe}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) } +
      %w[README.md CHANGELOG.md LICENSE.txt].select { |f| File.exist?(f) }
  end
  spec.require_paths = ["lib"]

  # No third-party runtime dependencies — intentional. ostruct is a stdlib
  # bundled gem (Ruby >= 3.5) and must be declared to be requirable;
  # CompletionMetadata builds on it.
  # dry-types may be added as an optional enhancement in the future.
  spec.add_dependency "ostruct", "~> 0.6"
end
