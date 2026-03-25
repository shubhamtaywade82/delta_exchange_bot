# frozen_string_literal: true

require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dotenv"
Dotenv.load(".env.test") if File.exist?(".env.test")

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec
  config.order = :random
end
