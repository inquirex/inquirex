# frozen_string_literal: true

module Inquirex
  # Evaluates rule AST nodes against a given answer context.
  # Rule objects implement Rules::Base#evaluate.
  #
  # @attr_reader answers [Hash] current answer state (step_id => value)
  class Evaluator
    attr_reader :answers

    # @param answers [Hash] answer context to evaluate rules against
    def initialize(answers)
      @answers = answers
    end

    # Evaluates a single rule (or returns true if rule is nil).
    #
    # @param rule [Rules::Base, nil] rule to evaluate
    # @return [Boolean]
    def evaluate(rule)
      return true if rule.nil?

      rule.evaluate(@answers)
    end
  end
end
