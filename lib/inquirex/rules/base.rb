# frozen_string_literal: true

module Inquirex
  module Rules
    # Abstract base for rule AST nodes. Subclasses implement #evaluate and #to_s
    # for use in transitions and visibility conditions.
    # Rules are immutable and serialize to/from JSON for cross-platform evaluation.
    class Base
      # Evaluates the rule against the current answer context.
      #
      # @param _answers [Hash] step_id => value
      # @return [Boolean]
      def evaluate(_answers)
        raise NotImplementedError, "#{self.class}#evaluate must be implemented"
      end

      # Serializes the rule to a plain Hash for JSON serialization.
      #
      # @return [Hash]
      def to_h
        raise NotImplementedError, "#{self.class}#to_h must be implemented"
      end

      # Human-readable representation (e.g. for graph labels).
      #
      # @return [String]
      def to_s
        raise NotImplementedError, "#{self.class}#to_s must be implemented"
      end

      # Deserializes a rule from a plain Hash (e.g. parsed from JSON).
      #
      # @param hash [Hash] rule hash with string or symbol keys
      # @return [Rules::Base] the deserialized rule
      # @raise [Inquirex::Errors::SerializationError] on unknown operator
      def self.from_h(hash)
        op = hash["op"] || hash[:op]
        case op.to_s
        when "contains"   then Contains.from_h(hash)
        when "equals"     then Equals.from_h(hash)
        when "greater_than" then GreaterThan.from_h(hash)
        when "less_than"  then LessThan.from_h(hash)
        when "not_empty"  then NotEmpty.from_h(hash)
        when "all"        then All.from_h(hash)
        when "any"        then Any.from_h(hash)
        else
          raise Inquirex::Errors::SerializationError, "Unknown rule operator: #{op.inspect}"
        end
      end
    end
  end
end
