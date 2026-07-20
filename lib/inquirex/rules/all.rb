# frozen_string_literal: true

module Inquirex
  # Namespace for rule AST nodes used in transitions and visibility conditions.
  module Rules
    # Composite rule: logical AND of multiple sub-rules. All must be true.
    class All < Base
      attr_reader :rules

      # @param rules [Array<Rules::Base>] sub-rules that must all hold
      def initialize(*rules)
        super()
        @rules = rules.flatten.freeze
        freeze
      end

      # True when every sub-rule evaluates true (vacuously true when empty).
      #
      # @param answers [Hash{Symbol => Object}] answer context, step_id => value
      # @return [Boolean]
      def evaluate(answers)
        @rules.all? { |rule| rule.evaluate(answers) }
      end

      # @return [Hash{String => Object}] wire format with nested rule hashes
      def to_h
        { "op" => "all", "rules" => @rules.map(&:to_h) }
      end

      # @return [String] human-readable form, sub-rules joined with AND
      def to_s
        "(#{@rules.join(" AND ")})"
      end

      # Deserializes an All rule, recursively rehydrating its sub-rules.
      #
      # @param hash [Hash] rule hash with string or symbol keys
      # @return [All]
      def self.from_h(hash)
        raw_rules = hash["rules"] || hash[:rules] || []
        new(*raw_rules.map { |r| Base.from_h(r) })
      end
    end
  end
end
