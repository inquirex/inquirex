# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field (coerced to integer) is greater than the threshold.
    class GreaterThan < Base
      attr_reader :field, :value

      # @param field [Symbol, String] step id whose answer is compared
      # @param value [Integer] threshold the answer must exceed
      def initialize(field, value)
        super()
        @field = field.to_sym
        @value = value
        freeze
      end

      # True when the field's answer, coerced to an Integer, exceeds the threshold.
      #
      # @param answers [Hash{Symbol => Object}] answer context, step_id => value
      # @return [Boolean]
      def evaluate(answers)
        answers[@field].to_i > @value
      end

      # @return [Hash{String => Object}] wire format, same shape .from_h accepts
      def to_h
        { "op" => "greater_than", "field" => @field.to_s, "value" => @value }
      end

      # @return [String] human-readable form, e.g. "dependents > 2"
      def to_s
        "#{@field} > #{@value}"
      end

      # Deserializes a GreaterThan rule from a plain Hash.
      #
      # @param hash [Hash] rule hash with string or symbol keys
      # @return [GreaterThan]
      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        value = (hash["value"] || hash[:value]).to_i
        new(field, value)
      end
    end
  end
end
