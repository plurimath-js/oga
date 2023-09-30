require 'rspec'
require 'stringio'

if ENV['COVERAGE']
  require_relative 'support/simplecov'
end

if RUBY_PLATFORM == 'opal'
  require_relative 'support/opal_support'
end

require 'oga'
require_relative 'support/parsing_helpers'
require_relative 'support/evaluation_helpers'
require_relative 'support/threading_helpers'

RSpec.configure do |config|
  config.color = true

  config.include Oga::ParsingHelpers
  config.include Oga::EvaluationHelpers
  config.include Oga::ThreadingHelpers
end
