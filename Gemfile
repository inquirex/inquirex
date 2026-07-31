# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in inquirex.gemspec
gemspec

gem "irb"
gem "rake"

# Soft runtime dependency of the deprecated Actions::SendEmail effect,
# required only when a message is built. Listed here so the specs can
# exercise Mail building.
gem "mail"

# NOT a dependency of this gem, and deliberately not one: the top-level
# send_email verb stores Liquid templates and never renders them. It is here
# so the specs can exercise Inquirex::Email's "the host has Liquid loaded"
# path against the real thing rather than a stand-in. The "no Liquid
# anywhere" path is covered by stubbing the same seam.
gem "base64" # liquid 5.x requires it, and it is no longer a default gem
gem "liquid"

gem "rspec"
gem "rspec-its"

gem "rubocop"
gem "rubocop-rspec"
gem "coverage-badge"
gem "simplecov"

gem "yard"
