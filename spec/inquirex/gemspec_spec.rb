# frozen_string_literal: true

# A library the gem requires at load time must be a declared runtime
# dependency. prism stopped being a default gem in Ruby 4.1 and reached this
# repository's bundle only through rubocop, so the suite stayed green while
# every consumer's `require "inquirex"` raised LoadError.
RSpec.describe "inquirex.gemspec" do
  let(:gemspec) { Gem::Specification.load(File.expand_path("../../inquirex.gemspec", __dir__)) }
  let(:runtime) { gemspec.runtime_dependencies.map(&:name) }

  it "declares every standard-library gem lib/ requires that is not a default gem" do
    expect(runtime).to include("ostruct", "prism")
  end
end
