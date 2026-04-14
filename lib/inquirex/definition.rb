# frozen_string_literal: true

require "json"

module Inquirex
  # Immutable, versionable flow graph. Maps step ids to Node objects and defines the entry point.
  # Carries optional metadata (id, version, title, subtitle, brand) for the JS widget.
  # Supports JSON round-trip serialization; lambdas are stripped on serialization.
  #
  # @attr_reader id [String, nil] flow identifier (e.g. "tax-intake-2025")
  # @attr_reader version [String] semver string (default: "1.0.0")
  # @attr_reader meta [Hash] title, subtitle, brand info for the frontend
  # @attr_reader start_step_id [Symbol] id of the first step in the flow
  # @attr_reader steps [Hash<Symbol, Node>] frozen map of step id => node
  class Definition
    attr_reader :id, :version, :meta, :start_step_id, :steps, :accumulators

    # @param start_step_id [Symbol] id of the initial step
    # @param nodes [Hash<Symbol, Node>] all steps keyed by id
    # @param id [String, nil] flow identifier
    # @param version [String] semver
    # @param meta [Hash] frontend metadata
    # @param accumulators [Hash<Symbol, Accumulator>] named running totals
    # @raise [Errors::DefinitionError] if start_step_id is not present in nodes
    def initialize(start_step_id:, nodes:, id: nil, version: "1.0.0", meta: {}, accumulators: {})
      @id = id
      @version = version
      @meta = meta.freeze
      @start_step_id = start_step_id.to_sym
      @steps = nodes.freeze
      @accumulators = accumulators.freeze
      validate!
      freeze
    end

    # @return [Node] the node for the start step
    def start_step
      step(@start_step_id)
    end

    # @param id [Symbol] step id
    # @return [Node] the node for that step
    # @raise [Errors::UnknownStepError] if id is not in steps
    def step(id)
      @steps.fetch(id.to_sym) { raise Errors::UnknownStepError, "Unknown step: #{id.inspect}" }
    end

    # @return [Array<Symbol>] all step ids
    def step_ids
      @steps.keys
    end

    # Serializes the definition to a JSON string.
    # Lambdas (default procs, compute blocks) are silently stripped.
    #
    # @return [String] JSON representation
    def to_json(*)
      JSON.generate(to_h)
    end

    # Serializes to a plain Hash.
    #
    # @return [Hash]
    def to_h
      hash = {}
      hash["id"] = @id if @id
      hash["version"] = @version
      hash["meta"] = @meta unless @meta.empty?
      hash["start"] = @start_step_id.to_s
      unless @accumulators.empty?
        hash["accumulators"] = @accumulators.each_with_object({}) do |(name, acc), h|
          h[name.to_s] = acc.to_h
        end
      end
      hash["steps"] = @steps.transform_keys(&:to_s).transform_values(&:to_h)
      hash
    end

    # Deserializes a Definition from a JSON string.
    #
    # @param json [String] JSON representation
    # @return [Definition]
    def self.from_json(json)
      from_h(JSON.parse(json))
    rescue JSON::ParserError => e
      raise Errors::SerializationError, "Invalid JSON: #{e.message}"
    end

    # Deserializes a Definition from a plain Hash.
    #
    # @param hash [Hash] definition attributes (string or symbol keys)
    # @return [Definition]
    def self.from_h(hash)
      id = hash["id"] || hash[:id]
      version = hash["version"] || hash[:version] || "1.0.0"
      meta = hash["meta"] || hash[:meta] || {}
      start = hash["start"] || hash[:start]
      steps_data = hash["steps"] || hash[:steps] || {}
      acc_data = hash["accumulators"] || hash[:accumulators] || {}

      nodes = steps_data.each_with_object({}) do |(step_id, step_hash), acc|
        sym_id = step_id.to_sym
        acc[sym_id] = Node.from_h(sym_id, step_hash)
      end

      accumulators = acc_data.each_with_object({}) do |(name, entry), h|
        sym = name.to_sym
        h[sym] = Accumulator.from_h(sym, entry)
      end

      new(start_step_id: start, nodes:, id:, version:, meta:, accumulators:)
    end

    private

    def validate!
      return if @steps.key?(@start_step_id)

      raise Errors::DefinitionError, "Start step #{@start_step_id.inspect} not found in steps"
    end
  end
end
