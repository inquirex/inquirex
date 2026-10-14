# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in inquirex.gemspec
gemspec

# Soft runtime dependency of Actions::SendEmail — required only when a
# message is built. Listed here so the specs can exercise Mail building.
gem "mail"

group :development, :test do
  gem "bundle-audit"
  gem "rake"

  gem "rspec"
  gem "rspec-its"

  gem "rubocop"
  gem "rubocop-rspec"
  gem "coverage-badge"
  gem "simplecov"

  gem "yard"
end
