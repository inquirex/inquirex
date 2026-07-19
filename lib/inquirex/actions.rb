# frozen_string_literal: true

module Inquirex
  # Post-completion actions: named side-effect declarations that run
  # server-side after a flow finishes, with access to the collected answers.
  #
  # The DSL word `action` groups one or more *effects* (send_email, run, ...).
  # Effects are looked up in a registry keyed by their DSL verb, so new effect
  # types — a webhook, a save_record in inquirex-rails — plug in without core
  # changes: register the class and it gains both the DSL word and JSON wire
  # support.
  #
  #   Inquirex::Actions.register(:webhook, MyGem::WebhookEffect)
  #
  # Actions never deliver anything themselves. send_email builds Mail::Message
  # objects into Answers#outbox; the host application decides how to send them.
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
