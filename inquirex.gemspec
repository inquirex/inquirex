# frozen_string_literal: true

require_relative "lib/inquirex/version"

Gem::Specification.new do |spec|
  spec.name = "inquirex"
  spec.version = Inquirex::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "A declarative, rules-driven questionnaire engine for building conditionally-branching intake forms, qualification wizards, and surveys in pure Ruby."
  spec.description = "Inquirex lets you define multi-step questionnaires as directed graphs with conditional branching, using a conversational DSL (ask, say, mention) and an AST-based rule system (contains, equals, greater_than, all, any). The engine walks the graph, collects structured answers, and serializes everything to JSON — making it the ideal backbone for cross-platform intake forms where the frontend is a chat widget, a terminal, or a mobile app. Framework-agnostic, zero dependencies, thread-safe immutable definitions."
  spec.homepage = "https://github.com/inquirex/inquirex"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/inquirex/inquirex"
  spec.metadata["changelog_uri"] = "https://github.com/inquirex/inquirex/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.require_paths = ["lib"]

  # Zero required runtime dependencies — intentional.
  # dry-types may be added as an optional enhancement in the future.
end
