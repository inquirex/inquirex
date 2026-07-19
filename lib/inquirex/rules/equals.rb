# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field equals the given value.
    class Equals < Base
      attr_reader :field, :value

      # @param field [Symbol, String] step id whose answer is compared
      # @param value [Object] value the answer must equal
      def initialize(field, value)
        super()
        @field = field.to_sym
        @value = value
        freeze
      end

      # True when the field's answer equals the value (Ruby ==).
      #
      # @param answers [Hash{Symbol => Object}] answer context, step_id => value
      # @return [Boolean]
      def evaluate(answers)
        answers[@field] == @value
      end

      # @return [Hash{String => Object}] wire format, same shape .from_h accepts
      def to_h
        { "op" => "equals", "field" => @field.to_s, "value" => @value }
      end

      # @return [String] human-readable form, e.g. "filing_status == single"
      def to_s
        "#{@field} == #{@value}"
      end

      # Deserializes an Equals rule from a plain Hash.
      #
      # @param hash [Hash] rule hash with string or symbol keys
      # @return [Equals]
      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        value = hash["value"] || hash[:value]
        new(field, value)
      end
    end
  end
end
