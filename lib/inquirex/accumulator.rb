# frozen_string_literal: true

module Inquirex
  # Declares a named running total (e.g. :price, :complexity, :credit_score) that
  # flows accumulate into as the user answers questions. Pure data, serializable
  # to JSON, evaluated identically on Ruby and JS sides.
  #
  # A `:text` accumulator is different in kind: nothing declares `accumulate`
  # into it, and no Accumulation ever targets it. The Engine appends to it
  # automatically as the user moves through the flow — every display step's
  # text, and every question with the answer given to it. That running
  # narrative is what an LLM `summarize` step reads, and it is the only way a
  # flow that mostly *tells* the user things (a help or explainer flow) has
  # anything to summarize at all: such a flow collects few answers, so the
  # answers hash alone says nothing about what the user was shown.
  #
  # @attr_reader name [Symbol] accumulator identifier (e.g. :price)
  # @attr_reader type [Symbol] one of Node::TYPES (typically :currency, :integer, :decimal, :text)
  # @attr_reader default [Numeric, String] starting value (0, or "" when :text)
  #
  # @example Declare a running price total and contribute to it from a step
  #   Inquirex.define do
  #     accumulator :price, type: :currency, default: 0
  #     ask :dependents do
  #       type :integer
  #       accumulate :price, per_unit: 50
  #     end
  #   end
  #
  # @example Declare a transcript the engine fills in on its own
  #   Inquirex.define do
  #     accumulator :transcript, type: :text
  #     say(:intro) { text "Here is how depreciation works." }
  #   end
  #   # engine.advance
  #   # engine.text(:transcript)  # => "Here is how depreciation works."
  class Accumulator
    # The accumulator type whose running value is appended prose rather than
    # a running total. See the class docs for why it exists.
    TEXT_TYPE = :text

    attr_reader :name, :type, :default

    # @param name [Symbol, String] accumulator identifier
    # @param type [Symbol, String] value type, one of Node::TYPES
    # @param default [Numeric, String, nil] starting value before any
    #   contributions; nil selects the type's own zero ("" for :text, else 0)
    def initialize(name:, type: :decimal, default: nil)
      @name = name.to_sym
      @type = type.to_sym
      @default = default.nil? ? zero_value : default
      freeze
    end

    # Whether this accumulator accumulates prose rather than a running total.
    # Text accumulators are filled by the Engine, never by an Accumulation.
    #
    # @return [Boolean]
    def text?
      @type == TEXT_TYPE
    end

    # Serializes the accumulator to its wire format. The name is omitted —
    # Definition#to_h keys the accumulators map by name.
    #
    # @return [Hash{String => Object}] e.g. { "type" => "currency", "default" => 0 }
    def to_h
      { "type" => @type.to_s, "default" => @default }
    end

    # Deserializes an Accumulator from its wire format.
    #
    # @param name [Symbol, String] accumulator identifier (the map key)
    # @param hash [Hash] type/default attributes (string or symbol keys)
    # @return [Accumulator]
    def self.from_h(name, hash)
      # `fetch`, not `||` — a text accumulator's serialized default is "",
      # which `||` would discard in favour of the numeric zero.
      default = hash.fetch("default") { hash.fetch(:default, nil) }
      new(
        name:    name,
        type:    hash["type"] || hash[:type] || :decimal,
        default: default
      )
    end

    private

    # The starting value implied by the type when none was declared.
    #
    # @return [Numeric, String]
    def zero_value
      text? ? "" : 0
    end
  end

  # Per-step declaration of how a single answer contributes to one accumulator.
  # A Node may carry zero or more Accumulation entries, one per target accumulator.
  #
  # Supported shapes (exactly one must be set):
  #   lookup:        Hash of answer_value => amount (for :enum)
  #   per_selection: Hash of option_value => amount (for :multi_enum, summed)
  #   per_unit:      Numeric rate multiplied by the answer (for numeric types)
  #   flat:          Numeric amount added if the step has any answer
  #
  # @attr_reader target [Symbol] accumulator name to contribute to (e.g. :price)
  # @attr_reader shape [Symbol] one of :lookup, :per_selection, :per_unit, :flat
  # @attr_reader payload [Object] shape-specific data (Hash or Numeric)
  class Accumulation
    # Valid accumulation shapes; exactly one must be declared per entry.
    SHAPES = %i[lookup per_selection per_unit flat].freeze

    attr_reader :target, :shape, :payload

    # @param target [Symbol, String] accumulator name to contribute to
    # @param shape [Symbol, String] one of SHAPES
    # @param payload [Hash, Numeric] shape-specific data (Hash for :lookup/:per_selection)
    # @raise [Errors::DefinitionError] when shape is not one of SHAPES
    def initialize(target:, shape:, payload:)
      @target = target.to_sym
      @shape = shape.to_sym
      raise Errors::DefinitionError, "Unknown accumulator shape: #{shape.inspect}" unless SHAPES.include?(@shape)

      @payload = self.class.send(:normalize_payload, @shape, payload).freeze
      freeze
    end

    # Computes this accumulation's contribution given the step's answer.
    # Returns 0 when the answer is absent or does not match the shape.
    #
    # @param answer [Object] the user's answer for the owning step
    # @return [Numeric]
    def contribution(answer)
      return 0 if answer.nil?

      case @shape
      when :lookup        then lookup_amount(answer)
      when :per_selection then selection_amount(answer)
      when :per_unit      then unit_amount(answer)
      when :flat          then flat_amount(answer)
      end
    end

    # Serializes to the single-key shape Hash that .from_h accepts.
    #
    # @return [Hash{String => Object}] e.g. { "per_unit" => 50 }
    def to_h
      { @shape.to_s => serialize_payload }
    end

    # Parses a single-key Hash like `{ "lookup" => {...} }` into an Accumulation.
    #
    # @param target [Symbol, String] accumulator name
    # @param hash [Hash] serialized shape (string or symbol keys)
    # @return [Accumulation]
    def self.from_h(target, hash)
      pair = hash.to_a.find { |k, _| SHAPES.include?(k.to_sym) }
      raise Errors::SerializationError, "Invalid accumulation entry: #{hash.inspect}" unless pair

      shape_key, payload = pair
      new(target: target, shape: shape_key.to_sym, payload: payload)
    end

    def self.normalize_payload(shape, payload)
      case shape
      when :lookup, :per_selection
        (payload || {}).each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      else
        payload
      end
    end
    private_class_method :normalize_payload

    private

    def serialize_payload
      case @shape
      when :lookup, :per_selection
        @payload.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      else
        @payload
      end
    end

    def lookup_amount(answer)
      @payload[answer.to_s] || 0
    end

    def selection_amount(answer)
      return 0 unless answer.is_a?(Array)

      answer.sum { |selected| @payload[selected.to_s] || 0 }
    end

    def unit_amount(answer)
      numeric = numeric_for(answer)
      return 0 if numeric.nil?

      numeric * @payload
    end

    def flat_amount(answer)
      return 0 if answer == false
      return 0 if answer.respond_to?(:empty?) && answer.empty?

      @payload
    end

    def numeric_for(value)
      case value
      when Numeric then value
      when String  then Float(value, exception: false)
      end
    end
  end
end
