# frozen_string_literal: true

module Inquirex
  # Runtime session that drives flow navigation. Holds the definition, collected answers,
  # and current position in the flow graph.
  #
  # Collecting steps (ask, confirm): call engine.answer(value)
  # Display steps (say, header, btw, warning): call engine.advance
  #
  # Validates each answer via an optional Validation::Adapter, then advances using
  # node transitions. Skips steps whose skip_if rule evaluates to true.
  class Engine
    attr_reader :definition, :answers, :history, :current_step_id, :totals

    # @param definition [Definition] the flow to run
    # @param validator [Validation::Adapter] optional (default: NullAdapter)
    def initialize(definition, validator: Validation::NullAdapter.new)
      @definition = definition
      @answers = {}
      @history = []
      @current_step_id = definition.start_step_id
      @validator = validator
      @totals = init_totals
      @history << @current_step_id
      skip_display_steps_if_needed
    end

    # Convenience accessor for a single accumulator's running total.
    #
    # @param name [Symbol] accumulator name (e.g. :price)
    # @return [Numeric]
    def total(name)
      @totals[name.to_sym] || 0
    end

    # @return [Node, nil] current step node, or nil if flow is finished
    def current_step
      return nil if finished?

      @definition.step(@current_step_id)
    end

    # @return [Boolean] true when there is no current step (flow ended)
    def finished?
      @current_step_id.nil?
    end

    # Submits an answer for the current collecting step (ask/confirm).
    # Validates, stores, and advances to the next step.
    #
    # @param value [Object] user's answer for the current step
    # @raise [Errors::AlreadyFinishedError] if the flow has already finished
    # @raise [Errors::NonCollectingStepError] if the current step is a display verb
    # @raise [Errors::ValidationError] if the validator rejects the value
    def answer(value)
      raise Errors::AlreadyFinishedError, "Flow is already finished" if finished?
      raise Errors::NonCollectingStepError, "Step #{@current_step_id} is a display step; use #advance instead" \
        unless current_step.collecting?

      result = @validator.validate(current_step, value)
      raise Errors::ValidationError, "Validation failed: #{result.errors.join(", ")}" unless result.valid?

      @answers[@current_step_id] = value
      apply_accumulations(current_step, value)
      advance_step
    end

    # Advances past the current non-collecting step (say/header/btw/warning).
    #
    # @raise [Errors::AlreadyFinishedError] if the flow has already finished
    def advance
      raise Errors::AlreadyFinishedError, "Flow is already finished" if finished?

      advance_step
    end

    # Merges a hash of { step_id => value } into the top-level answers without
    # clobbering answers the user has already provided. Used by LLM clarify
    # steps to populate downstream answers from free-text extraction so that
    # `skip_if not_empty(:id)` rules on later steps will fire.
    #
    # Nil/empty values in the hash are ignored so that "unknown" LLM outputs
    # don't spuriously satisfy `not_empty` rules.
    #
    # If the engine's current step becomes skippable as a result of the prefill,
    # it auto-advances past it.
    #
    # @param hash [Hash] answers keyed by step id
    # @return [Hash] the updated answers
    def prefill!(hash)
      return @answers unless hash.is_a?(Hash)

      hash.each do |key, value|
        next if value.nil?
        next if value.respond_to?(:empty?) && value.empty?

        sym = key.to_sym
        @answers[sym] = value unless @answers.key?(sym)
      end
      skip_if_needed unless finished?
      @answers
    end

    # Serializable state snapshot for persistence or resumption.
    #
    # @return [Hash]
    def to_state
      {
        current_step_id: @current_step_id,
        answers:         @answers,
        history:         @history,
        totals:          @totals
      }
    end

    # Rebuilds an Engine from a previously saved state.
    #
    # @param definition [Definition] same definition used when state was captured
    # @param state_hash [Hash] hash with state keys (may be strings from JSON)
    # @param validator [Validation::Adapter]
    # @return [Engine]
    def self.from_state(definition, state_hash, validator: Validation::NullAdapter.new)
      state = StateSerializer.symbolize_state(state_hash)
      engine = allocate
      engine.send(:restore_state, definition, state, validator)
      engine
    end

    private

    def restore_state(definition, state, validator)
      @definition = definition
      @validator = validator
      @current_step_id = state[:current_step_id]
      @answers = state[:answers] || {}
      @history = state[:history] || []
      @totals = state[:totals] || init_totals
    end

    def init_totals
      @definition.accumulators.each_with_object({}) do |(name, acc), h|
        h[name] = acc.default
      end
    end

    def apply_accumulations(node, answer)
      node.accumulations.each do |accumulation|
        @totals[accumulation.target] ||= 0
        @totals[accumulation.target] += accumulation.contribution(answer)
      end
    end

    def advance_step
      node = @definition.step(@current_step_id)
      next_id = node.next_step_id(@answers)
      @current_step_id = next_id
      return unless next_id

      @history << next_id
      skip_if_needed
    end

    # Auto-skips the current step if its skip_if rule is satisfied.
    def skip_if_needed
      return if finished?

      node = @definition.step(@current_step_id)
      return unless node.skip?(@answers)

      advance_step
    end

    # On initialization, skip any display steps that appear before the first collecting step
    # if their skip_if condition is met. Display steps are not skipped by default on init —
    # the caller decides when to advance past them.
    def skip_display_steps_if_needed
      skip_if_needed
    end
  end
end
