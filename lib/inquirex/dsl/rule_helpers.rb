# frozen_string_literal: true

module Inquirex
  module DSL
    # Factory methods for rule objects. Included in FlowBuilder and StepBuilder
    # so these helpers are available inside flow/step blocks.
    module RuleHelpers
      # @param field [Symbol] answer key (step id)
      # @param value [Object] value to check for in the array answer
      # @return [Rules::Contains]
      def contains(field, value)
        Rules::Contains.new(field, value)
      end

      # @param field [Symbol] answer key
      # @param value [Object] expected exact value
      # @return [Rules::Equals]
      def equals(field, value)
        Rules::Equals.new(field, value)
      end

      # @param field [Symbol] answer key (value coerced to integer)
      # @param value [Integer] threshold
      # @return [Rules::GreaterThan]
      def greater_than(field, value)
        Rules::GreaterThan.new(field, value)
      end

      # @param field [Symbol] answer key (value coerced to integer)
      # @param value [Integer] threshold
      # @return [Rules::LessThan]
      def less_than(field, value)
        Rules::LessThan.new(field, value)
      end

      # @param field [Symbol] answer key
      # @return [Rules::NotEmpty]
      def not_empty(field)
        Rules::NotEmpty.new(field)
      end

      # Logical AND: all rules must be true.
      # @param rules [Array<Rules::Base>]
      # @return [Rules::All]
      def all(*rules)
        Rules::All.new(*rules)
      end

      # Logical OR: at least one rule must be true.
      # @param rules [Array<Rules::Base>]
      # @return [Rules::Any]
      def any(*rules)
        Rules::Any.new(*rules)
      end
    end
  end
end
