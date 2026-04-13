# frozen_string_literal: true

require "json"

module Inquirex
  # Structured wrapper around the answers collected during flow execution.
  # Provides dot-notation access, bracket access, dig with dot-separated keys,
  # and serialization helpers.
  #
  # @example
  #   answers = Inquirex::Answers.new({ filing_status: "single", business: { count: 3 } })
  #   answers.filing_status          # => "single"
  #   answers[:filing_status]        # => "single"
  #   answers.business.count         # => 3 (nested dot-notation)
  #   answers.dig("business.count")  # => 3
  #   answers.to_flat_h              # => { "filing_status" => "single", "business.count" => 3 }
  class Answers
    # @param data [Hash] flat or nested hash of answers (symbol or string keys)
    def initialize(data = {})
      @data = deep_symbolize(data).freeze
    end

    # Bracket access (symbol or string key).
    #
    # @param key [Symbol, String]
    # @return [Object, Answers, nil]
    def [](key)
      wrap(@data[key.to_sym])
    end

    # Dot-notation access.
    #
    # @raise [NoMethodError] if the key does not exist (like a real method would)
    def method_missing(name, *args)
      return super if args.any? || !@data.key?(name)

      wrap(@data[name])
    end

    def respond_to_missing?(name, include_private = false)
      @data.key?(name) || super
    end

    # Dig using dot-separated key string or sequential keys.
    #
    # @param keys [Array<String, Symbol>] path components or a single dot-separated string
    # @return [Object, nil]
    def dig(*keys)
      parts = keys.length == 1 ? keys.first.to_s.split(".").map(&:to_sym) : keys.map(&:to_sym)
      parts.reduce(@data) do |current, key|
        return nil unless current.is_a?(Hash)

        current[key]
      end
    end

    # @return [Hash] nested hash with symbol keys
    def to_h
      @data.dup
    end

    # @return [Hash] flat hash with string dot-notation keys
    def to_flat_h
      flatten_hash(@data)
    end

    # @return [String] JSON representation
    def to_json(*)
      JSON.generate(stringify_keys(@data))
    end

    # @return [Boolean]
    def ==(other)
      case other
      when Answers then @data == other.to_h
      when Hash    then @data == deep_symbolize(other)
      else false
      end
    end

    # @return [Boolean] true when no answers have been collected
    def empty?
      @data.empty?
    end

    # Number of top-level answer keys.
    def size
      @data.size
    end

    # Merge another hash or Answers into this one (returns new Answers instance).
    #
    # @param other [Hash, Answers]
    # @return [Answers]
    def merge(other)
      other_data = other.is_a?(Answers) ? other.to_h : deep_symbolize(other)
      Answers.new(@data.merge(other_data))
    end

    def inspect
      "#<Inquirex::Answers #{@data.inspect}>"
    end

    private

    def wrap(value)
      value.is_a?(Hash) ? Answers.new(value) : value
    end

    def deep_symbolize(hash)
      hash.each_with_object({}) do |(k, v), result|
        result[k.to_sym] = v.is_a?(Hash) ? deep_symbolize(v) : v
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), result|
        result[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v
      end
    end

    def flatten_hash(hash, prefix = nil)
      hash.each_with_object({}) do |(k, v), result|
        full_key = prefix ? "#{prefix}.#{k}" : k.to_s
        if v.is_a?(Hash)
          result.merge!(flatten_hash(v, full_key))
        else
          result[full_key] = v
        end
      end
    end
  end
end
