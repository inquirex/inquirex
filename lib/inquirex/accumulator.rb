# frozen_string_literal: true

module Inquirex
  # Declares a named running total (e.g. :price, :complexity, :credit_score) that
  # flows accumulate into as the user answers questions. Pure data, serializable
  # to JSON, evaluated identically on Ruby and JS sides.
  #
  # @attr_reader name [Symbol] accumulator identifier (e.g. :price)
  # @attr_reader type [Symbol] one of Node::TYPES (typically :currency, :integer, :decimal)
  # @attr_reader default [Numeric] starting value (default: 0)
  class Accumulator
    attr_reader :name, :type, :default

    def initialize(name:, type: :decimal, default: 0)
      @name = name.to_sym
      @type = type.to_sym
      @default = default
      freeze
    end

    def to_h
      { "type" => @type.to_s, "default" => @default }
    end

    def self.from_h(name, hash)
      new(
        name:    name,
        type:    hash["type"] || hash[:type] || :decimal,
        default: hash["default"] || hash[:default] || 0
      )
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
    SHAPES = %i[lookup per_selection per_unit flat].freeze

    attr_reader :target, :shape, :payload

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
