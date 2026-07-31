# frozen_string_literal: true

module Inquirex
  # Runtime session that drives flow navigation. Holds the definition, collected answers,
  # and current position in the flow graph.
  #
  # Collecting steps (ask, confirm): call engine.answer(value)
  # Display steps (say, header, btw, warning): call engine.advance
  # Optional steps (declared `required false`): engine.skip is also allowed
  #
  # Validates each answer via an optional Validation::Adapter, then advances using
  # node transitions. Skips steps whose skip_if rule evaluates to true.
  class Engine
    attr_reader :definition, :answers, :history, :current_step_id, :totals

    # Metadata describing how and where the flow was completed. Rendering
    # front-ends (TTY, web, chat widget) attach a rich version from an
    # after_completion hook; when no hook provides one, the engine stamps a
    # minimal core version the moment the flow finishes. Only :engine and
    # :engine_version are required members; everything else is free-form.
    #
    # @return [CompletionMetadata, nil] nil until the flow finishes
    attr_accessor :completion_metadata

    # Answer suggestions produced by prefill! for multi-select steps, keyed by
    # step id. A suggestion pre-populates the step's choices in a renderer but
    # — unlike an answer — never satisfies skip_if rules: multi-select
    # extraction is treated as a hint the user confirms and may extend, not a
    # deterministic fact. Cleared per step once the user answers it.
    #
    # @return [Hash{Symbol => Array}]
    attr_reader :suggestions

    # Step ids the user explicitly skipped via #skip, in the order they were
    # skipped. Distinguishes default-by-skip values in answers from values the
    # user actually provided. Steps elided automatically by their skip_if rule
    # are NOT listed here — they were never presented, so the user cannot have
    # declined them.
    #
    # @return [Array<Symbol>]
    attr_reader :skipped

    # Exceptions raised by after_completion hooks, in the order they were
    # raised. Hooks are isolated from one another, so a raising hook is
    # recorded here rather than propagated — callers that care can inspect
    # this after the flow finishes. Empty when every hook succeeded.
    #
    # @return [Array<StandardError>]
    attr_reader :completion_hook_errors

    # @param definition [Definition] the flow to run
    # @param validator [Validation::Adapter] optional (default: NullAdapter)
    def initialize(definition, validator: Validation::NullAdapter.new)
      @definition = definition
      @answers = {}
      @history = []
      @current_step_id = definition.start_step_id
      @validator = validator
      @totals = init_totals
      @completion_metadata = nil
      @after_completion_hooks = []
      @completion_hook_errors = []
      @suggestions = {}
      @skipped = []
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
      @suggestions.delete(@current_step_id)
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

    # Skips the current optional collecting step at the user's request — the
    # engine-side handler for a widget's Skip button. Only steps declared with
    # `required false` may be skipped.
    #
    # When the step has a default, the default is recorded into the answers and
    # contributes to accumulators exactly as if the user had submitted it; the
    # step id lands in #skipped so consumers can tell the value apart from one
    # the user actually provided. Without a default, no answers entry is
    # written (rules read a missing key as nil, so branching is unaffected).
    # Advances through transitions exactly like #answer.
    #
    # @example Optional question, skipped by the user
    #   engine.current_step.required?  # => false
    #   engine.skip
    #   engine.answers[:dependents]    # => 0 (the step's default)
    #   engine.skipped                 # => [:dependents]
    #
    # @return [void]
    # @raise [Errors::AlreadyFinishedError] if the flow has already finished
    # @raise [Errors::NonCollectingStepError] if the current step is a display verb
    # @raise [Errors::RequiredStepError] if the current step is required
    def skip
      raise Errors::AlreadyFinishedError, "Flow is already finished" if finished?
      raise Errors::NonCollectingStepError, "Step #{@current_step_id} is a display step; use #advance instead" \
        unless current_step.collecting?
      raise Errors::RequiredStepError, "Step #{@current_step_id} is required and cannot be skipped" \
        if current_step.required?

      node = current_step
      default = resolve_default(node)
      unless default.nil?
        @answers[@current_step_id] = default
        apply_accumulations(node, default)
      end
      @skipped << @current_step_id unless @skipped.include?(@current_step_id)
      @suggestions.delete(@current_step_id)
      advance_step
    end

    # Whether the user explicitly skipped the given step via #skip.
    #
    # @param step_id [Symbol, String] step id
    # @return [Boolean]
    def skipped?(step_id)
      @skipped.include?(step_id.to_sym)
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
        if multi_select_step?(sym)
          # Multi-select extraction is a hint, not a fact: the user may have
          # more selections in mind than the text revealed. Record it as a
          # suggestion so renderers pre-check the choices while the question
          # is still asked; skip_if rules see no answer and do not fire.
          @suggestions[sym] = Array(value) unless @answers.key?(sym)
        else
          @answers[sym] = value unless @answers.key?(sym)
        end
      end
      skip_if_needed unless finished?
      @answers
    end

    # The prefill suggestion for a step, or nil when none was recorded.
    #
    # @param step_id [Symbol, String] step id
    # @return [Array, nil] suggested selections for a multi-select step
    def suggestion_for(step_id)
      @suggestions[step_id.to_sym]
    end

    # Registers a hook to run when the flow finishes. The block receives the
    # engine; front-ends typically use it to attach a rich
    # completion_metadata (host, user, ips, terminal, ...). Optional — after
    # all hooks run, the engine fills in a minimal CompletionMetadata when
    # none of them provided one. Registering on an already-finished engine
    # invokes the block immediately.
    #
    # Any number of hooks may be registered; they run in registration order.
    # Each is isolated from the others — a hook that raises a StandardError
    # has it recorded in #completion_hook_errors, and the remaining hooks
    # still run. Non-StandardError exceptions (Interrupt, SignalException)
    # propagate, as they should.
    #
    # @example Stamp renderer-specific completion metadata
    #   engine.after_completion do |eng|
    #     eng.completion_metadata = Inquirex::CompletionMetadata.new(
    #       engine: "inquirex-tty", engine_version: "0.5.0", hostname: Socket.gethostname
    #     )
    #   end
    #
    # @yield [Engine] the engine, at completion time
    # @return [Engine] self
    def after_completion(&block)
      raise ArgumentError, "after_completion requires a block" unless block

      @after_completion_hooks << block
      if finished?
        invoke_completion_hook(block)
        ensure_completion_metadata
      end
      self
    end

    # Serializable state snapshot for persistence or resumption.
    #
    # @return [Hash]
    def to_state
      {
        current_step_id:     @current_step_id,
        answers:             @answers,
        history:             @history,
        totals:              @totals,
        suggestions:         @suggestions,
        skipped:             @skipped,
        completion_metadata: @completion_metadata&.to_h
      }
    end

    # The collected answers with the completion metadata (when a renderer
    # attached one) merged in under the :completion_metadata key, and the
    # user-skipped step ids (when any) under the :skipped key — so
    # post-completion actions and API consumers can tell default-by-skip
    # values apart from answers the user actually provided.
    #
    # @return [Hash]
    def answers_with_metadata
      extra = {}
      extra[:completion_metadata] = @completion_metadata.to_h if @completion_metadata
      extra[:skipped] = @skipped.dup unless @skipped.empty?
      extra.empty? ? @answers : @answers.merge(extra)
    end

    # The data a host binds when rendering this flow's Liquid strings — the
    # `question` of the current step, the `text` of a display step, or a
    # `send_email` template.
    #
    # Plain and JSON-serializable: keys are Strings, Symbol values become
    # Strings, nesting is preserved. Take it fresh at **display time**, not at
    # load time: answers and totals accumulate as the wizard progresses, so
    # `question "Thanks {{ answers.name }}, what is your email?"` can only be
    # rendered once :name has been collected.
    #
    # @example Rendering the current question in a host that has Liquid
    #   Liquid::Template.parse(engine.current_step.question)
    #                   .render(engine.render_context)
    #
    # @return [Hash{String => Object}] `"answers"` and `"accumulators"`
    def render_context
      {
        "answers"      => jsonify(@answers),
        "accumulators" => jsonify(@totals)
      }
    end

    # What the completed flow *asks* the host to do — currently the flow's
    # `send_email` declarations, each as a plain, JSON-serializable Hash.
    #
    # The list is **advisory**. The gem sends nothing, builds no message and
    # tracks no delivery; a host may process all of it, some of it or none of
    # it. That framing is what lets new action types (a webhook, a CRM push) be
    # added without breaking anyone: a host loops over the array and handles
    # the `"type"` values it recognizes.
    #
    # Templates are returned **raw**, paired with a `"context"` snapshot equal
    # to {#render_context}. The gem cannot render them — it has no Liquid and
    # no Markdown converter, by design (see {Email}) — and shipping the context
    # alongside makes each entry self-contained: a background job can pick one
    # up minutes later, with no engine and no session, and still have
    # everything it needs. The cost is that the context repeats per action,
    # which is the right trade for a payload measured in kilobytes.
    #
    # Empty until the flow finishes.
    #
    # @example What a host enqueues
    #   engine.on_complete_actions
    #   # => [{ "type"          => "send_email",
    #   #       "to"            => "{{ answers.email }}",
    #   #       "from"          => "Qualified.At",
    #   #       "subject"       => "Thank you for filling the form",
    #   #       "body_markdown" => "Dear {{ answers.name }},\n",
    #   #       "context"       => { "answers"      => { "name" => "Ada", "email" => "ada@x.io" },
    #   #                            "accumulators" => { "price" => 240.0 } } }]
    #
    # @example What a host does with it
    #   engine.on_complete_actions.each do |action|
    #     next unless action["type"] == "send_email"
    #
    #     OutboundMailJob.perform_later(action)  # renders Liquid + Markdown, then delivers
    #   end
    #
    # @return [Array<Hash{String => Object}>] ordered as declared; empty until
    #   {#finished?}
    def on_complete_actions
      return [] unless finished?

      context = render_context.freeze
      @definition.emails.map { |email| email.to_action(context) }
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

    # Normalizes collected data into what JSON would make of it, so that a
    # render context (or an enqueued action) survives a round-trip through a
    # job queue unchanged: Symbol keys and Symbol values become Strings,
    # nesting is preserved, everything else passes through.
    #
    # @param value [Object]
    # @return [Object]
    def jsonify(value)
      case value
      when Hash   then value.each_with_object({}) { |(key, item), acc| acc[key.to_s] = jsonify(item) }
      when Array  then value.map { |item| jsonify(item) }
      when Symbol then value.to_s
      else value
      end
    end

    def restore_state(definition, state, validator)
      @definition = definition
      @validator = validator
      @current_step_id = state[:current_step_id]
      @answers = state[:answers] || {}
      @history = state[:history] || []
      @totals = state[:totals] || init_totals
      @completion_metadata = CompletionMetadata.from_h(state[:completion_metadata])
      @after_completion_hooks = []
      @completion_hook_errors = []
      @suggestions = state[:suggestions] || {}
      @skipped = state[:skipped] || []
    end

    # Whether +step_id+ names a multi-select step in the definition. Unknown
    # ids (e.g. an extract schema field that matches no step) are not.
    #
    # @param step_id [Symbol]
    # @return [Boolean]
    def multi_select_step?(step_id)
      @definition.step_ids.include?(step_id) && @definition.step(step_id).type == :multi_enum
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

    # The step's default as a concrete value: a Proc default (server-side only,
    # stripped from JSON) is called with the answers collected so far, exactly
    # as a renderer pre-filling the field would resolve it.
    #
    # @param node [Node]
    # @return [Object, nil]
    def resolve_default(node)
      default = node.default
      return default unless default.is_a?(Proc)

      default.arity.zero? ? default.call : default.call(@answers)
    end

    def advance_step
      node = @definition.step(@current_step_id)
      next_id = node.next_step_id(@answers)
      @current_step_id = next_id
      return run_after_completion_hooks unless next_id

      @history << next_id
      skip_if_needed
    end

    # Fires the moment the flow finishes: runs registered after_completion
    # hooks in registration order, then guarantees completion_metadata exists
    # — hooks may attach a rich version; absent that (including when the hook
    # meant to supply it raised), a minimal core-stamped one is used.
    def run_after_completion_hooks
      @after_completion_hooks.each { |hook| invoke_completion_hook(hook) }
      ensure_completion_metadata
      nil
    end

    # Runs one hook in isolation. A StandardError is recorded rather than
    # propagated so that one misbehaving hook cannot silently cancel the
    # hooks registered after it, nor abort the completion of the flow itself.
    def invoke_completion_hook(hook)
      hook.call(self)
    rescue StandardError => e
      @completion_hook_errors << e
    end

    def ensure_completion_metadata
      return if @completion_metadata

      @completion_metadata = CompletionMetadata.new(engine: "inquirex", engine_version: VERSION)
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
