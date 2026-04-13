# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field (coerced to integer) is less than the threshold.
    class LessThan < Base
      attr_reader :field, :value

      def initialize(field, value)
        super()
        @field = field.to_sym
        @value = value
        freeze
      end

      def evaluate(answers)
        answers[@field].to_i < @value
      end

      def to_h
        { "op" => "less_than", "field" => @field.to_s, "value" => @value }
      end

      def to_s
        "#{@field} < #{@value}"
      end

      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        value = (hash["value"] || hash[:value]).to_i
        new(field, value)
      end
    end
  end
end
