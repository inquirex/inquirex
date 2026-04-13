# frozen_string_literal: true

module Inquirex
  module Rules
    # Composite rule: logical AND of multiple sub-rules. All must be true.
    class All < Base
      attr_reader :rules

      def initialize(*rules)
        super()
        @rules = rules.flatten.freeze
        freeze
      end

      def evaluate(answers)
        @rules.all? { |rule| rule.evaluate(answers) }
      end

      def to_h
        { "op" => "all", "rules" => @rules.map(&:to_h) }
      end

      def to_s
        "(#{@rules.join(" AND ")})"
      end

      def self.from_h(hash)
        raw_rules = hash["rules"] || hash[:rules] || []
        new(*raw_rules.map { |r| Base.from_h(r) })
      end
    end
  end
end
