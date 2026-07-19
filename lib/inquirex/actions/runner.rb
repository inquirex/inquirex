# frozen_string_literal: true

module Inquirex
  module Actions
    # Executes a definition's actions against completed answers, in
    # declaration order, populating Answers#outbox with built messages and a
    # result trail.
    #
    # Deliberately separate from the Engine: in the cross-site architecture
    # the frontend collects answers and a different server process
    # post-processes them, so the runner is a pure function of
    # (definition, answers) — which also makes rebuilding messages inside a
    # background job trivial.
    #
    # A failing effect records a :failed result and never aborts the other
    # actions; the host inspects outbox.failures and decides what to do.
    class Runner
      # @param definition [Definition]
      def initialize(definition)
        @definition = definition
      end

      # @param answers [Answers, Hash] completed answers (a Hash is wrapped)
      # @return [Answers] the (possibly wrapped) answers with #outbox populated
      def call(answers)
        answers = Answers.new(answers) unless answers.is_a?(Answers)
        context = answers.to_h

        @definition.actions.each do |action|
          unless action.applicable?(context)
            answers.outbox.record(action.id, :skipped)
            next
          end
          execute(action, answers)
        end

        answers
      end

      private

      def execute(action, answers)
        action.effects.each do |effect|
          effect.call(answers, answers.outbox)
          answers.outbox.record(action.id, :ok)
        rescue StandardError => e
          answers.outbox.record(action.id, :failed, error: e)
        end
      end
    end
  end
end
