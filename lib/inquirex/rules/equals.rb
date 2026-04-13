# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field equals the given value.
    class Equals < Base
      attr_reader :field, :value

      def initialize(field, value)
        super()
        @field = field.to_sym
        @value = value
        freeze
      end

      def evaluate(answers)
        answers[@field] == @value
      end

      def to_h
        { "op" => "equals", "field" => @field.to_s, "value" => @value }
      end

      def to_s
        "#{@field} == #{@value}"
      end

      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        value = hash["value"] || hash[:value]
        new(field, value)
      end
    end
  end
end
