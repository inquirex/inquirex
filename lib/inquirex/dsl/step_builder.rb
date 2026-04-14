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
        @widget_hints = {}
        @accumulations = []
      end

      # Declares how this step's answer contributes to a named accumulator.
      # Exactly one shape key should be provided:
      #   lookup:        Hash of answer_value => amount (for :enum)
      #   per_selection: Hash of option_value => amount (for :multi_enum)
      #   per_unit:      Numeric rate (multiplied by the numeric answer)
      #   flat:          Numeric (added when the step has any answer)
      #
      # @example
      #   accumulate :price, lookup: { single: 200, mfj: 400 }
      #   accumulate :price, per_unit: 25
      #   accumulate :price, per_selection: { c: 150, e: 75 }
      #   accumulate :complexity, flat: 1
      def accumulate(target, lookup: nil, per_selection: nil, per_unit: nil, flat: nil)
        shape, payload = pick_accumulator_shape(lookup:, per_selection:, per_unit:, flat:)
        @accumulations << Accumulation.new(target:, shape:, payload:)
      end

      # Sugar for the common `:price` accumulator. Accepts either a shape keyword
      # (`lookup:`, `per_selection:`, `per_unit:`, `flat:`) or — when given plain
      # option=>amount keys — treats it as a `lookup`. So both work:
      #
      #   price single: 200, mfj: 400           # => lookup
      #   price per_unit: 25                    # => per_unit
      #   price lookup: { single: 200, ... }    # => lookup (explicit)
      def price(**kwargs)
        shape_keys = %i[lookup per_selection per_unit flat]
        if kwargs.keys.intersect?(shape_keys)
          accumulate(:price, **kwargs.slice(*shape_keys))
        else
          accumulate(:price, lookup: kwargs)
        end
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

      # Sets a rendering hint for the given target context.
      # Recognized targets: :desktop, :mobile, :tty (and any future targets).
      #
      # @param type [Symbol] widget type (e.g. :radio_group, :dropdown)
      # @param target [Symbol] rendering context (default: :desktop)
      # @param opts [Hash] widget-specific options (e.g. columns: 2)
      #
      # @example
      #   widget target: :desktop, type: :radio_group, columns: 2
      #   widget target: :mobile,  type: :dropdown
      #   widget target: :tty,     type: :select
      def widget(type:, target: :desktop, **opts)
        @widget_hints[target.to_sym] = WidgetHint.new(type:, options: opts)
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
          verb:          @verb,
          type:          resolve_type,
          question:      @question,
          text:          @text,
          options:       @options,
          transitions:   @transitions,
          skip_if:       @skip_if,
          default:       @default,
          widget_hints:  resolve_widget_hints,
          accumulations: @accumulations
        )
      end

      private

      def pick_accumulator_shape(lookup:, per_selection:, per_unit:, flat:)
        provided = { lookup:, per_selection:, per_unit:, flat: }.compact
        if provided.size != 1
          raise Errors::DefinitionError,
            "accumulate requires exactly one of :lookup, :per_selection, :per_unit, :flat (got #{provided.keys})"
        end
        provided.first
      end

      def resolve_type
        # :confirm is sugar for :ask with type :boolean
        return :boolean if @verb == :confirm && @type.nil?

        @type
      end

      # Fills in registry defaults for targets not explicitly set (collecting steps only).
      # Display verbs get nil widget_hints.
      def resolve_widget_hints
        effective_type = resolve_type
        return nil if effective_type.nil? && @widget_hints.empty?

        hints = @widget_hints.dup
        %i[desktop mobile].each do |target|
          hints[target] ||= WidgetRegistry.default_hint_for(effective_type, context: target)
        end
        hints.compact!
        hints.empty? ? nil : hints
      end
    end
  end
end
