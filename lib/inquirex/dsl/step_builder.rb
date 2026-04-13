# frozen_string_literal: true

module Inquirex
  module DSL
    # Builds a single Node from a step DSL block. Used by FlowBuilder for each verb
    # (ask, say, header, btw, warning, confirm). Includes RuleHelpers for transition
    # conditions and skip_if expressions.
    class StepBuilder
      include RuleHelpers

      def initialize(verb)
        @verb = verb
        @type = nil
        @question = nil
        @text = nil
        @options = nil
        @transitions = []
        @skip_if = nil
        @default = nil
        @compute = nil
      end

      # Sets the input data type for :ask steps.
      # @param value [Symbol] one of Node::TYPES
      def type(value)
        @type = value
      end

      # Sets the prompt/question text for collecting steps.
      # @param text [String]
      def question(text)
        @question = text
      end

      # Sets the display text for non-collecting steps (say/header/btw/warning).
      # @param content [String]
      def text(content)
        @text = content
      end

      # Sets the list of options for :enum or :multi_enum steps.
      # Accepts an Array (option keys) or a Hash (key => label).
      # @param list [Array, Hash]
      def options(list)
        @options = list
      end

      # Adds a conditional transition. First matching transition wins.
      #
      # @param to [Symbol] target step id
      # @param if_rule [Rules::Base, nil] condition (nil = unconditional)
      # @param requires_server [Boolean] whether this transition needs server round-trip
      def transition(to:, if_rule: nil, requires_server: false)
        @transitions << Transition.new(target: to, rule: if_rule, requires_server:)
      end

      # Sets a rule that skips this step entirely when true.
      # The step is omitted from the user's path and no answer is recorded.
      #
      # @param rule [Rules::Base]
      def skip_if(rule)
        @skip_if = rule
      end

      # Sets a default value for this step (shown pre-filled; user can change it).
      # Can be a static value or a proc receiving collected answers so far.
      #
      # @param value [Object, Proc]
      def default(value = nil, &block)
        @default = block || value
      end

      # Registers a compute block: auto-calculates a value from answers, not shown to user.
      # The computed value is stored server-side only and stripped from JSON serialization.
      #
      # @yield [Answers] block receiving answers, must return the computed value
      def compute(&block)
        @compute = block
      end

      # Builds the Node for the given step id.
      #
      # @param id [Symbol]
      # @return [Node]
      def build(id)
        Node.new(
          id:,
          verb:        @verb,
          type:        resolve_type,
          question:    @question,
          text:        @text,
          options:     @options,
          transitions: @transitions,
          skip_if:     @skip_if,
          default:     @default
        )
      end

      private

      def resolve_type
        # :confirm is sugar for :ask with type :boolean
        return :boolean if @verb == :confirm && @type.nil?

        @type
      end
    end
  end
end
