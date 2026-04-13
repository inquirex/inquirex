# frozen_string_literal: true

module Inquirex
  # A single edge from one step to another, optionally guarded by a rule.
  # Transitions are evaluated in order; the first whose rule is true determines the next step.
  # Can carry a `requires_server` flag for steps that need a server round-trip (e.g. LLM steps).
  #
  # @attr_reader target [Symbol] id of the step to go to when this transition applies
  # @attr_reader rule [Rules::Base, nil] condition; nil means unconditional (always applies)
  # @attr_reader requires_server [Boolean] whether this transition needs a server round-trip
  class Transition
    attr_reader :target, :rule, :requires_server

    # @param target [Symbol] next step id
    # @param rule [Rules::Base, nil] optional condition (nil = always)
    # @param requires_server [Boolean] whether this edge needs server evaluation
    def initialize(target:, rule: nil, requires_server: false)
      @target = target.to_sym
      @rule = rule
      @requires_server = requires_server
      freeze
    end

    # Human-readable label for the condition.
    #
    # @return [String] rule#to_s or "always"
    def condition_label
      @rule ? @rule.to_s : "always"
    end

    # Whether this transition should be taken given current answers.
    #
    # @param answers [Hash] current answer state
    # @return [Boolean] true if rule is nil or rule evaluates to true
    def applies?(answers)
      return true if @rule.nil?

      @rule.evaluate(answers)
    end

    # Serializes to a plain Hash for JSON output.
    #
    # @return [Hash]
    def to_h
      hash = { "to" => @target.to_s }
      hash["rule"] = @rule.to_h if @rule
      hash["requires_server"] = true if @requires_server
      hash
    end

    # Deserializes from a plain Hash.
    #
    # @param hash [Hash] with string or symbol keys
    # @return [Transition]
    def self.from_h(hash)
      target = hash["to"] || hash[:to]
      rule_hash = hash["rule"] || hash[:rule]
      requires_server = hash["requires_server"] || hash[:requires_server] || false
      rule = rule_hash ? Rules::Base.from_h(rule_hash) : nil
      new(target:, rule:, requires_server:)
    end
  end
end
