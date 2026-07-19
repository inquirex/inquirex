# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field is present and not empty.
    class NotEmpty < Base
      attr_reader :field

      # @param field [Symbol, String] step id whose answer is checked for presence
      def initialize(field)
        super()
        @field = field.to_sym
        freeze
      end

      # True when the field's answer is neither nil nor empty
      # (empty String, Array, Hash, etc. all evaluate false).
      #
      # @param answers [Hash{Symbol => Object}] answer context, step_id => value
      # @return [Boolean]
      def evaluate(answers)
        val = answers[@field]
        return false if val.nil?
        return false if val.respond_to?(:empty?) && val.empty?

        true
      end

      # @return [Hash{String => Object}] wire format, same shape .from_h accepts
      def to_h
        { "op" => "not_empty", "field" => @field.to_s }
      end

      # @return [String] human-readable form, e.g. "income_types is not empty"
      def to_s
        "#{@field} is not empty"
      end

      # Deserializes a NotEmpty rule from a plain Hash.
      #
      # @param hash [Hash] rule hash with string or symbol keys
      # @return [NotEmpty]
      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        new(field)
      end
    end
  end
end
