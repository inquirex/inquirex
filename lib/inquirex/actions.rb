# frozen_string_literal: true

module Inquirex
  # Post-completion actions: named side-effect declarations that run
  # server-side after a flow finishes, with access to the collected answers.
  #
  # The DSL word `action` groups one or more *effects*, looked up in a registry
  # keyed by their DSL verb, so a host gem can add an effect type without core
  # changes: register the class and it gains both the DSL word and JSON wire
  # support.
  #
  #   Inquirex::Actions.register(:save_record, MyGem::SaveRecordEffect)
  #
  # Actions never deliver anything themselves. {SendEmail} builds
  # Mail::Message objects into Answers#outbox; the host decides how to send.
  #
  # @deprecated Retained in 0.7.0 only so flow definitions hosts already store
  #   keep loading; removal is planned for 0.8.0. New flows declare a
  #   {Inquirex::Email top-level `send_email` block}, which the gem serializes
  #   and the host renders — no `mail` gem, no template engine, nothing to
  #   execute. Two effects were removed outright in 0.7.0 because their entire
  #   purpose was executing something a stored definition named: `run`
  #   (arbitrary Ruby) and `webhook` (an SSRF primitive whose destination host
  #   was authorized by the same untrusted document).
  module Actions
    @registry = {}

    class << self
      # Registers an effect class under a DSL verb name.
      #
      # @param type [Symbol] DSL verb (e.g. :send_email)
      # @param klass [Class] an Actions::Base subclass
      def register(type, klass)
        @registry[type.to_sym] = klass
      end

      # @param type [Symbol, String]
      # @return [Boolean]
      def registered?(type)
        @registry.key?(type.to_sym)
      end

      # @param type [Symbol, String]
      # @return [Class]
      # @raise [Errors::SerializationError] for unknown effect types
      def lookup(type)
        @registry.fetch(type.to_sym) do
          raise Errors::SerializationError, "Unknown action effect type: #{type.inspect}"
        end
      end

      # @return [Array<Symbol>] registered effect verbs
      def types = @registry.keys

      # Runs all of the definition's actions against the given answers.
      #
      # @param definition [Definition]
      # @param answers [Answers, Hash]
      # @return [Answers] with #outbox populated
      def run(definition, answers)
        Runner.new(definition).call(answers)
      end
    end
  end
end
