# frozen_string_literal: true

module Inquirex
  module DSL
    # Builds an Actions::Action from an `action` DSL block. Every effect verb
    # registered in Inquirex::Actions (send_email, plus anything host gems
    # register) is available as a method automatically.
    #
    #   action :admin_alert do
    #     send_email to: "admin@example.com", subject: "New lead: {{name}}",
    #                html: "{{answers_summary}}"
    #   end
    #
    # @deprecated Along with the whole `action` verb — see
    #   {FlowBuilder#action}. New flows declare a top-level `send_email` block
    #   instead.
    class ActionBuilder
      def initialize
        @effects = []
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
