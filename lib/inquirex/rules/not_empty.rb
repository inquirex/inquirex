# frozen_string_literal: true

module Inquirex
  module Rules
    # Rule: the answer for the given field is present and not empty.
    class NotEmpty < Base
      attr_reader :field

      def initialize(field)
        super()
        @field = field.to_sym
        freeze
      end

      def evaluate(answers)
        val = answers[@field]
        return false if val.nil?
        return false if val.respond_to?(:empty?) && val.empty?

        true
      end

      def to_h
        { "op" => "not_empty", "field" => @field.to_s }
      end

      def to_s
        "#{@field} is not empty"
      end

      def self.from_h(hash)
        field = hash["field"] || hash[:field]
        new(field)
      end
    end
  end
end
