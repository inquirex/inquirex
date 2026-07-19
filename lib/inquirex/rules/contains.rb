# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field (as an array) includes the given value.
    # Used for multi_enum steps (e.g. "Business in income_types").
    class Contains < Base
      attr_reader :field, :value

      # @param field [Symbol, String] step id whose answer is inspected
      # @param value [Object] value the answer must include
      def initialize(field, value)
        super()
        @field = field.to_sym
        @value = value
        freeze
      end

      # True when the field's answer, coerced to an Array, includes the value.
      #
      # @param answers [Hash{Symbol => Object}] answer context, step_id => value
      # @return [Boolean]
      def evaluate(answers)
        Array(answers[@field]).include?(@value)
      end

      # @return [Hash{String => Object}] wire format, same shape .from_h accepts
      def to_h
        { "op" => "contains", "field" => @field.to_s, "value" => @value }
      end

      # @return [String] human-readable form, e.g. "Business in income_types"
      def to_s
        "#{@value} in #{@field}"
      end

      # Deserializes a Contains rule from a plain Hash.
      #
      # @param hash [Hash] rule hash with string or symbol keys
      # @return [Contains]
      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        value = hash["value"] || hash[:value]
        new(field, value)
      end
    end
  end
end
