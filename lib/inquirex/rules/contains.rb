# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field (as an array) includes the given value.
    # Used for multi_enum steps (e.g. "Business in income_types").
    class Contains < Base
      attr_reader :field, :value

      def initialize(field, value)
        super()
        @field = field.to_sym
        @value = value
        freeze
      end

      def evaluate(answers)
        Array(answers[@field]).include?(@value)
      end

      def to_h
        { "op" => "contains", "field" => @field.to_s, "value" => @value }
      end

      def to_s
        "#{@value} in #{@field}"
      end

      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        value = hash["value"] || hash[:value]
        new(field, value)
      end
    end
  end
end
