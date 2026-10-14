# frozen_string_literal: true

require "simplecov"
require "coverage/badge"
require "rspec/its"

SimpleCov.skip /spec/
SimpleCov.start do
  self.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    Coverage::Badge::Formatter
  ]
end

SimpleCov.at_exit do
  SimpleCov.result.format!
  # rubocop: disable-next RSpec/Output
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
  FileUtils.mkdir_p("docs/badges/")
  FileUtils.mv("coverage/badge.svg", "docs/badges/coverage_badge.svg")
end

require "inquirex"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.order = :random
  Kernel.srand config.seed
end
