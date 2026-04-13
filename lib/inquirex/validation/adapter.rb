# frozen_string_literal: true

module Inquirex
  module Validation
    # Result of validating a step answer.
    #
    # @attr_reader errors [Array<String>] validation error messages (empty when valid)
    class Result
      attr_reader :errors

      # @param valid [Boolean]
      # @param errors [Array<String>]
      def initialize(valid:, errors: [])
        @valid = valid
        @errors = errors.freeze
        freeze
      end

      # @return [Boolean]
      def valid?
        @valid
      end
    end

    # Abstract adapter for step-level validation. Implement #validate to plug in
    # dry-validation, ActiveModel::Validations, JSON Schema, or any other validator.
    class Adapter
      # @param _node [Node] the current step (for schema/constraints)
      # @param _input [Object] value submitted by the user
      # @return [Result]
      def validate(_node, _input)
        raise NotImplementedError, "#{self.class}#validate must be implemented"
      end
    end
  end
end
