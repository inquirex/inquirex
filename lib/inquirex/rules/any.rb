# frozen_string_literal: true

module Inquirex
  module Rules
    # Composite rule: logical OR of multiple sub-rules. At least one must be true.
    class Any < Base
      attr_reader :rules

      # @param rules [Array<Rules::Base>] sub-rules, at least one of which must hold
      def initialize(*rules)
        super()
        @rules = rules.flatten.freeze
        freeze
      end

      # True when at least one sub-rule evaluates true (false when empty).
      #
      # @param answers [Hash{Symbol => Object}] answer context, step_id => value
      # @return [Boolean]
      def evaluate(answers)
        @rules.any? { |rule| rule.evaluate(answers) }
      end

      # @return [Hash{String => Object}] wire format with nested rule hashes
      def to_h
        { "op" => "any", "rules" => @rules.map(&:to_h) }
      end

      # @return [String] human-readable form, sub-rules joined with OR
      def to_s
        "(#{@rules.join(" OR ")})"
      end

      # Deserializes an Any rule, recursively rehydrating its sub-rules.
      #
      # @param hash [Hash] rule hash with string or symbol keys
      # @return [Any]
      def self.from_h(hash)
        raw_rules = hash["rules"] || hash[:rules] || []
        new(*raw_rules.map { |r| Base.from_h(r) })
      end
    end
  end
end
