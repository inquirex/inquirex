# frozen_string_literal: true

module Inquirex
  module DSL
    # Builds an Actions::Action from an `action` DSL block. Every effect verb
    # registered in Inquirex::Actions (send_email, plus anything host gems
    # register) is available as a method automatically; `run` wraps arbitrary
    # Ruby in an Actions::Custom effect.
    #
    #   action :admin_alert do
    #     send_email to: "admin@example.com", subject: "New lead: {{name}}",
    #                html: "{{answers_summary}}"
    #     run { |answers, outbox| Metrics.count(:lead, answers.to_flat_h) }
    #   end
    class ActionBuilder
      def initialize
        @effects = []
      end

      # Escape hatch: arbitrary server-side Ruby. Stripped from JSON.
      #
      # @yield [answers, outbox]
      def run(&block)
        raise Errors::DefinitionError, "run requires a block" unless block

        @effects << Actions::Custom.new(block)
      end

      # Registered effect verbs (send_email, ...) resolve dynamically so that
      # newly registered effect types become DSL words without core changes.
      def method_missing(name, *args, **params, &)
        return super unless Actions.registered?(name)

        raise Errors::DefinitionError, "#{name} takes keyword arguments only" unless args.empty?

        @effects << Actions.lookup(name).new(**params)
      end

      def respond_to_missing?(name, include_private = false)
        Actions.registered?(name) || super
      end

      # @param id [Symbol]
      # @param rule [Rules::Base, nil]
      # @return [Actions::Action]
      def build(id, rule: nil)
        raise Errors::DefinitionError, "action #{id.inspect} declares no effects" if @effects.empty?

        Actions::Action.new(id:, effects: @effects, rule:)
      end
    end
  end
end
