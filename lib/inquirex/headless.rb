# frozen_string_literal: true

module Inquirex
  # Runs a flow to the end from a hash of preset answers, with no terminal,
  # no prompt and no LLM: the driver behind `inquirex-tty run --answers` and
  # `--yes`, and the way to run a flow in tests and CI.
  #
  # Answers reach the engine through Engine#answer and Engine#skip only,
  # never Engine#prefill!. prefill! records a multi-select as a suggestion
  # that no skip_if rule can see, so a flow whose multi-select is gated on
  # its own answer would stop on that question with nobody to answer it.
  #
  # Step by step:
  #
  # - a display step advances silently;
  # - a step present in +answers+ is answered with that value, as given (an
  #   LLM step included: the value stands in for the adapter's output, and
  #   nothing is splatted into other answers);
  # - otherwise, with +yes+, a step with a default is answered with it (a
  #   Proc default resolved against the answers so far);
  # - otherwise an optional step is skipped, recording its default as
  #   Engine#skip does;
  # - otherwise, with +yes+, a required LLM step is answered with nil;
  # - otherwise the run stops with MissingAnswer naming the step.
  #
  # No LLM adapter is ever called: core has none, and a run under +yes+ is
  # meant to be offline and repeatable.
  #
  # @example Run a flow from an answers file's contents
  #   results = Inquirex::Headless.new(definition, answers: { filing_status: "single" }, yes: true).call
  #   results[:answers]     # => { filing_status: "single", dependents: 0, ... }
  #   results[:path_taken]  # => [:filing_status, :dependents, :done]
  class Headless
    # Raised when a step needs an answer that neither +answers+ nor (with
    # +yes+) a default supplies.
    class MissingAnswer < Errors::EngineError
      # @return [Symbol] the step left without an answer
      attr_reader :step_id

      # @param step_id [Symbol]
      def initialize(step_id)
        @step_id = step_id
        super("No answer for required step #{step_id.inspect}: give one in the answers, or a default with yes")
      end
    end

    # The engine the run drives. Register Engine#after_completion hooks on it
    # before #call to attach completion metadata.
    #
    # @return [Engine]
    attr_reader :engine

    # @param definition [Definition] the flow to run
    # @param answers [Hash{Symbol, String => Object}] preset answers by step id;
    #   string keys, as JSON and YAML produce them, are accepted
    # @param yes [Boolean] take each unanswered step's default
    def initialize(definition, answers: {}, yes: false)
      @engine = Engine.new(definition)
      @answers = answers.to_h { |step_id, value| [step_id.to_sym, value] }
      @yes = yes
    end

    # Drives the engine until the flow finishes.
    #
    # @return [Hash] +:path_taken+ (step ids, in order), +:answers+
    #   (Engine#answers_with_metadata) and +:steps_completed+. A caller adds
    #   whatever it knows that the engine does not, such as the flow file or a
    #   completion time.
    # @raise [MissingAnswer] when a step can be given no answer
    # @raise [Errors::ValidationError] when the validator rejects an answer
    def call
      take(@engine.current_step) until @engine.finished?
      results
    end

    private

    # Moves the engine past one step.
    #
    # @param node [Node]
    # @return [void]
    def take(node)
      return @engine.advance if node.display?
      return @engine.answer(@answers[node.id]) if @answers.key?(node.id)

      # Only under yes: resolving a Proc default runs host code.
      default = @yes ? @engine.current_default : nil
      return @engine.answer(default) unless default.nil?
      return @engine.skip unless node.required?
      return @engine.answer(nil) if @yes && llm_step?(node)

      raise MissingAnswer, node.id
    end

    # LLM steps come from inquirex-llm, which core does not load, so they are
    # recognised by the predicate their node class answers.
    #
    # @param node [Node]
    # @return [Boolean]
    def llm_step?(node) = node.respond_to?(:llm_verb?) && node.llm_verb?

    # @return [Hash]
    def results
      {
        path_taken:      @engine.history,
        answers:         @engine.answers_with_metadata,
        steps_completed: @engine.history.length
      }
    end
  end
end
