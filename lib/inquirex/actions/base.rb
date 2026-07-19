# frozen_string_literal: true

module Inquirex
  module Actions
    # Abstract base for action effects — the executable units inside an
    # `action` block. Subclasses implement #call and, when serializable,
    # #to_h / .from_h following the same round-trip pattern as Rules::Base.
    #
    # Effects that wrap Ruby procs (Actions::Custom) return false from
    # #serializable? and are stripped from JSON, consistent with how
    # lambdas are handled everywhere else in Inquirex.
    class Base
      # Executes the effect. Email-building effects append Mail::Message
      # objects to the outbox; custom effects may do anything server-side.
      #
      # @param answers [Answers] completed answers
      # @param outbox [Outbox] collector for built messages
      # @return [void]
      def call(answers, outbox)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      # @return [Boolean] whether this effect survives JSON serialization
      def serializable? = true

      # @return [Hash]
      def to_h
        raise NotImplementedError, "#{self.class}#to_h must be implemented"
      end
    end
  end
end
