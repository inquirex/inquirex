# frozen_string_literal: true

module Inquirex
  class Engine
    # Handles state serialization for Engine persistence (DB, session store, etc.).
    # Normalizes string-keyed hashes (from JSON round-trips) to symbol-keyed hashes.
    module StateSerializer
      SYMBOLIZERS = {
        current_step_id: ->(v) { v&.to_sym },
        history:         ->(v) { Array(v).map { |e| e&.to_sym } },
        answers:         ->(v) { symbolize_answers(v) },
        totals:          ->(v) { symbolize_answers(v) }
      }.freeze

      # Normalizes a state hash so step ids and history entries are symbols.
      #
      # @param hash [Hash] raw state (may have string keys from JSON)
      # @return [Hash] normalized state with symbol keys
      def self.symbolize_state(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          sym_key = key.to_sym
          result[sym_key] = SYMBOLIZERS.fetch(sym_key, ->(v) { v }).call(value)
        end
      end

      # @param answers [Hash] answers map (keys may be strings)
      # @return [Hash] same map with symbol keys
      def self.symbolize_answers(answers)
        return {} unless answers.is_a?(Hash)

        answers.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end
    end
  end
end
