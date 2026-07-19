# frozen_string_literal: true

module Inquirex
  module Actions
    # A named post-completion unit: an optional rule gating execution and an
    # ordered list of effects. Declared with the DSL word `action`:
    #
    #   action :client_receipt, if: not_empty(:email) do
    #     send_email to: "{{email}}", subject: "Thanks {{name}}!", text: "..."
    #   end
    #
    # Rules reuse the same serializable AST as transitions, so conditions
    # survive the JSON round-trip. Non-serializable effects (run blocks) are
    # stripped on serialization; an action left with no serializable effects
    # is omitted from JSON entirely.
    class Action
      attr_reader :id, :rule, :effects

      # @param id [Symbol] action identifier
      # @param effects [Array<Actions::Base>] executed in declaration order
      # @param rule [Rules::Base, nil] gate — action runs only when true
      def initialize(id:, effects:, rule: nil)
        @id = id.to_sym
        @effects = effects.freeze
        @rule = rule
        freeze
      end

      # @param answers_hash [Hash] step_id => value context for rule evaluation
      # @return [Boolean]
      def applicable?(answers_hash)
        @rule.nil? || @rule.evaluate(answers_hash)
      end

      # @return [Boolean] whether anything survives JSON serialization
      def serializable?
        @effects.any?(&:serializable?)
      end

      # @return [Hash] wire format; run blocks are stripped
      def to_h
        hash = { "id" => @id.to_s }
        hash["if"] = @rule.to_h if @rule
        hash["effects"] = @effects.select(&:serializable?).map(&:to_h)
        hash
      end

      # @param hash [Hash] string or symbol keys
      # @return [Action]
      def self.from_h(hash)
        id = hash["id"] || hash[:id]
        rule_data = hash["if"] || hash[:if]
        effects_data = hash["effects"] || hash[:effects] || []

        effects = effects_data.map do |effect_hash|
          type = effect_hash["type"] || effect_hash[:type]
          Actions.lookup(type).from_h(effect_hash)
        end

        new(
          id:      id.to_sym,
          effects: effects,
          rule:    rule_data ? Rules::Base.from_h(rule_data) : nil
        )
      end
    end
  end
end
