# frozen_string_literal: true

module Inquirex
  # A single step in the flow. The verb determines the role of this node:
  #
  # Collecting verbs (user provides input):
  #   :ask     — typed question with one of the 11 data types
  #   :confirm — yes/no boolean gate (shorthand for ask with type :boolean)
  #
  # Display verbs (no input, auto-advance):
  #   :say     — informational message
  #   :header  — section heading or title card
  #   :btw     — admonition, sidebar, or contextual note
  #   :warning — important alert
  #
  # @attr_reader id [Symbol] unique step identifier
  # @attr_reader verb [Symbol] DSL verb (:ask, :say, :header, :btw, :warning, :confirm)
  # @attr_reader type [Symbol, nil] input type for :ask/:confirm (nil for display verbs)
  # @attr_reader question [String, nil] prompt text for collecting steps
  # @attr_reader text [String, nil] display text for non-collecting steps
  # @attr_reader options [Array, nil] option keys for :enum/:multi_enum steps
  # @attr_reader option_labels [Hash, nil] key => display label mapping
  # @attr_reader transitions [Array<Transition>] ordered conditional next-step edges
  # @attr_reader skip_if [Rules::Base, nil] rule to skip this step entirely
  # @attr_reader default [Object, nil] default value (pre-fill, user can change)
  # @attr_reader widget_hints [Hash{Symbol => WidgetHint}, nil] rendering hints per target
  class Node
    # Valid DSL verbs and which ones collect input from the user.
    VERBS = %i[ask say header btw warning confirm].freeze
    COLLECTING_VERBS = %i[ask confirm].freeze
    DISPLAY_VERBS = %i[say header btw warning].freeze

    # Valid data types for :ask steps.
    TYPES = %i[
      string text integer decimal currency boolean
      enum multi_enum date email phone
    ].freeze

    attr_reader :id,
      :verb,
      :type,
      :question,
      :text,
      :options,
      :option_labels,
      :transitions,
      :skip_if,
      :default,
      :widget_hints

    def initialize(id:,
      verb:,
      type: nil,
      question: nil,
      text: nil,
      options: nil,
      transitions: [],
      skip_if: nil,
      default: nil,
      widget_hints: nil)
      @id = id.to_sym
      @verb = verb.to_sym
      @type = type&.to_sym
      @question = question
      @text = text
      @transitions = transitions.freeze
      @skip_if = skip_if
      @default = default
      @widget_hints = widget_hints&.freeze
      extract_options(options)
      freeze
    end

    # @return [Boolean] true if this step collects input from the user
    def collecting?
      COLLECTING_VERBS.include?(@verb)
    end

    # @return [Boolean] true if this step only displays content (no input)
    def display?
      DISPLAY_VERBS.include?(@verb)
    end

    # Returns the explicit widget hint for the given target, or nil.
    #
    # @param target [Symbol] e.g. :desktop, :mobile, :tty
    # @return [WidgetHint, nil]
    def widget_hint_for(target: :desktop)
      @widget_hints&.fetch(target.to_sym, nil)
    end

    # Returns the explicit hint for the target, falling back to the
    # registry default for this node's type when no explicit hint is set.
    #
    # @param target [Symbol] e.g. :desktop, :mobile, :tty
    # @return [WidgetHint, nil]
    def effective_widget_hint_for(target: :desktop)
      widget_hint_for(target:) || WidgetRegistry.default_hint_for(@type, context: target)
    end

    # Resolves the next step id from current answers by evaluating transitions in order.
    #
    # @param answers [Hash] current answer state
    # @return [Symbol, nil] id of the next step, or nil if no transition matches (flow end)
    def next_step_id(answers)
      match = @transitions.find { |t| t.applies?(answers) }
      match&.target
    end

    # Whether this step should be skipped given current answers.
    #
    # @param answers [Hash]
    # @return [Boolean]
    def skip?(answers)
      return false if @skip_if.nil?

      @skip_if.evaluate(answers)
    end

    # Serializes the node to a plain Hash for JSON output.
    # Lambda defaults/compute are stripped (server-side only).
    #
    # @return [Hash]
    def to_h
      hash = { "verb" => @verb.to_s }

      if collecting?
        hash["type"] = @type.to_s if @type
        hash["question"] = @question if @question
        hash["options"] = serialize_options if @options
        hash["skip_if"] = @skip_if.to_h if @skip_if
        hash["default"] = @default unless @default.nil? || @default.is_a?(Proc)
      elsif @text
        hash["text"] = @text
      end

      hash["transitions"] = @transitions.map(&:to_h) unless @transitions.empty?

      if @widget_hints && !@widget_hints.empty?
        hash["widget"] = @widget_hints.transform_keys(&:to_s)
                                      .transform_values(&:to_h)
      end

      hash
    end

    # Deserializes a node from a plain Hash.
    #
    # @param id [Symbol, String] step id
    # @param hash [Hash] node attributes
    # @return [Node]
    def self.from_h(id, hash)
      verb = hash["verb"] || hash[:verb]
      type = hash["type"] || hash[:type]
      question = hash["question"] || hash[:question]
      text = hash["text"] || hash[:text]
      raw_options = hash["options"] || hash[:options]
      transitions_data = hash["transitions"] || hash[:transitions] || []
      skip_if_data = hash["skip_if"] || hash[:skip_if]
      default = hash["default"] || hash[:default]
      widget_data = hash["widget"] || hash[:widget]

      transitions = transitions_data.map { |t| Transition.from_h(t) }
      skip_if = skip_if_data ? Rules::Base.from_h(skip_if_data) : nil
      options = deserialize_options(raw_options)
      widget_hints = deserialize_widget_hints(widget_data)

      new(
        id:,
        verb:,
        type:,
        question:,
        text:,
        options:,
        transitions:,
        skip_if:,
        default:,
        widget_hints:
      )
    end

    private

    def extract_options(raw)
      case raw
      when Hash
        @options = raw.keys.map(&:to_s).freeze
        @option_labels = raw.transform_keys(&:to_s).transform_values(&:to_s).freeze
      when Array
        if raw.first.is_a?(Hash)
          @options = raw.map { |o| (o["value"] || o[:value]).to_s }.freeze
          @option_labels = raw.to_h { |o| [(o["value"] || o[:value]).to_s, (o["label"] || o[:label]).to_s] }.freeze
        else
          @options = raw.map(&:to_s).freeze
          @option_labels = nil
        end
      else
        @options = nil
        @option_labels = nil
      end
    end

    def serialize_options
      if @option_labels
        @options.map { |v| { "value" => v, "label" => @option_labels[v] } }
      else
        @options.map { |v| { "value" => v, "label" => v } }
      end
    end

    def self.deserialize_options(raw)
      return nil if raw.nil?
      return raw unless raw.is_a?(Array)
      return raw if raw.empty?

      raw.to_h { |o| [(o["value"] || o[:value]).to_s, (o["label"] || o[:label]).to_s] }
    end
    private_class_method :deserialize_options

    def self.deserialize_widget_hints(widget_data)
      return nil unless widget_data.is_a?(Hash) && widget_data.any? { |_, v| v.is_a?(Hash) }

      widget_data.each_with_object({}) do |(target, hint_hash), acc|
        acc[target.to_sym] = WidgetHint.from_h(hint_hash)
      end
    end
    private_class_method :deserialize_widget_hints
  end
end
