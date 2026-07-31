# frozen_string_literal: true

module Inquirex
  module SafeSource
    # The registry of DSL words {Validator} accepts, and of the words it
    # deliberately refuses.
    #
    # Every entry is *bound to the builder that implements it*: the six flow
    # verbs are derived from {Node::VERBS}, step types from {Node::TYPES}, the
    # rule vocabulary from {DSL::RuleHelpers}, and each scope declares the
    # method list it governs (`vocabulary:`) so that {.undeclared_names} can
    # name any builder method nobody has made an allowlist decision about.
    # `spec/inquirex/safe_source/vocabulary_spec.rb` fails the build when that
    # list is non-empty — which is what stops this table drifting away from the
    # DSL it is supposed to describe.
    #
    # Downstream gems extend the vocabulary at boot rather than forking it.
    #
    # @example Teaching the allowlist about inquirex-llm's verbs
    #   V = Inquirex::SafeSource::Vocabulary
    #   V.register_scope(:llm_step, label: "an LLM step",
    #     vocabulary: -> { Inquirex::LLM::DSL::StepBuilder.public_instance_methods(false) })
    #   V.allow(:flow, :clarify, positional: %i[symbol], block: :llm_step)
    #   V.allow(:llm_step, :prompt, positional: %i[literal])
    #   V.exclude(:llm_step, :fallback, "a Ruby block cannot be validated")
    module Vocabulary
      # The only constant a flow definition may name.
      ENTRY_CONSTANT = :Inquirex

      # The only method that constant may receive.
      ENTRY_METHOD = :define

      # Keyword-descriptor key standing for "every keyword not named
      # explicitly". Legitimate only where the real method takes `**rest`.
      ANY_OTHER = :*

      # Value kinds a `transition` accepts. Shared by every step-like scope.
      TRANSITION_KEYWORDS = { to: :symbol, if_rule: :rule, requires_server: :literal }.freeze

      # Builder methods that exist for the builder's own sake and are not DSL
      # words, so they need no allowlist decision.
      PLUMBING = %i[build method_missing respond_to_missing?].freeze

      class << self
        # Declares a nested scope (idempotent): a block whose statements are
        # validated against their own table of calls.
        #
        # @param name [Symbol] scope name, e.g. :step
        # @param label [String] how to name the scope in a violation message,
        #   article included ("a step")
        # @param vocabulary [Proc, nil] returns the DSL words the scope's
        #   builder really implements; used by {.undeclared_names} to detect
        #   drift. Lazy, so load order does not matter.
        # @return [void]
        def register_scope(name, label:, vocabulary: nil)
          sym = name.to_sym
          @labels[sym] = label
          @vocabularies[sym] = vocabulary
          @calls[sym] ||= {}
          @exclusions[sym] ||= {}
        end

        # Allowlists one call inside one scope.
        #
        # @param scope [Symbol] scope name, e.g. :step
        # @param name [Symbol] DSL word, e.g. :question
        # @param positional [Array<Symbol>, Hash] see {CallSpec#positional}
        # @param keywords [nil, Hash] see {CallSpec#keywords}
        # @param block [Symbol] :forbidden, or the scope its block opens
        # @return [CallSpec] the registered spec
        # @raise [ArgumentError] when the scope was never registered
        def allow(scope, name, positional: [], keywords: nil, block: :forbidden)
          table = @calls.fetch(scope.to_sym) { raise ArgumentError, "Unknown SafeSource scope: #{scope.inspect}" }
          table[name.to_sym] = CallSpec.new(positional:, keywords:, block:)
        end

        # Records a DSL word that is knowingly *not* allowlisted, with the
        # reason — which {Validator} quotes back to the author, so a rejection
        # reads as a decision rather than an oversight.
        #
        # @param scope [Symbol] scope name
        # @param name [Symbol] DSL word, e.g. :compute
        # @param reason [String] why safe mode cannot accept it
        # @return [String] the reason
        # @raise [ArgumentError] when the scope was never registered
        def exclude(scope, name, reason)
          table = @exclusions.fetch(scope.to_sym) { raise ArgumentError, "Unknown SafeSource scope: #{scope.inspect}" }
          table[name.to_sym] = reason
        end

        # @param scope [Symbol]
        # @param name [Symbol]
        # @return [CallSpec, nil] nil when the call is not allowlisted
        def spec_for(scope, name)
          @calls.fetch(scope.to_sym, {})[name.to_sym]
        end

        # @param scope [Symbol]
        # @param name [Symbol]
        # @return [String, nil] why the call is excluded, nil when it was never
        #   part of the scope's vocabulary at all
        def exclusion_for(scope, name)
          @exclusions.fetch(scope.to_sym, {})[name.to_sym]
        end

        # @param scope [Symbol]
        # @return [String] the scope's human-readable label, article included
        def label_for(scope)
          @labels.fetch(scope.to_sym, "an unknown")
        end

        # @param name [Symbol]
        # @return [Boolean] whether the scope has been registered
        def scope?(name)
          @labels.key?(name.to_sym)
        end

        # @return [Array<Symbol>] every registered scope
        def scopes
          @labels.keys
        end

        # @param scope [Symbol]
        # @return [Array<Symbol>] every allowlisted call in the scope
        def allowed_names(scope)
          @calls.fetch(scope.to_sym, {}).keys
        end

        # @param scope [Symbol]
        # @return [Array<Symbol>] every knowingly excluded call in the scope
        def excluded_names(scope)
          @exclusions.fetch(scope.to_sym, {}).keys
        end

        # The DSL words the scope's builder implements, per the `vocabulary:`
        # binding given to {.register_scope}, minus builder plumbing.
        #
        # @param scope [Symbol]
        # @return [Array<Symbol>] empty when the scope declared no binding
        def governed_names(scope)
          @vocabularies.fetch(scope.to_sym, nil)&.call.to_a.map(&:to_sym) - PLUMBING
        end

        # Builder methods with no allowlist decision: neither allowed nor
        # knowingly excluded. Anything here is a new DSL word that silently
        # became unusable in safe mode (or, worse, an old one that quietly
        # gained a new meaning).
        #
        # @example Fail fast at boot
        #   raise "unreviewed DSL words" if V.scopes.any? { |s| V.undeclared_names(s).any? }
        #
        # @param scope [Symbol]
        # @return [Array<Symbol>]
        def undeclared_names(scope)
          governed_names(scope) - allowed_names(scope) - excluded_names(scope)
        end

        # Allowlist entries that no longer correspond to a real builder method
        # — a typo, or a DSL word that has since been removed or renamed.
        #
        # @param scope [Symbol]
        # @return [Array<Symbol>]
        def stale_names(scope)
          return [] if @vocabularies.fetch(scope.to_sym, nil).nil?

          (allowed_names(scope) + excluded_names(scope)) - governed_names(scope)
        end

        # The spec for `Inquirex.define` itself.
        #
        # @return [CallSpec]
        def entry_spec
          CallSpec.new(positional: [], keywords: { id: :string, version: :string }, block: :flow)
        end

        # Discards every registration and reinstalls the core vocabulary.
        # Hosts call this to undo an extension; the specs call it to isolate.
        #
        # @return [void]
        def reset!
          @labels = {}
          @calls = {}
          @exclusions = {}
          @vocabularies = {}
          install_core!
        end

        private

        # @return [void]
        def install_core!
          register_scope(:rule,
            label:      "a rule",
            vocabulary: -> { DSL::RuleHelpers.public_instance_methods(false) })
          register_scope(:flow,
            label:      "a flow",
            vocabulary: -> { DSL::FlowBuilder.public_instance_methods(false) })
          register_scope(:step,
            label:      "a step",
            vocabulary: -> { DSL::StepBuilder.public_instance_methods(false) })
          register_scope(:action,
            label:      "an action",
            vocabulary: -> { Actions.types + DSL::ActionBuilder.public_instance_methods(false) })

          install_rules!
          install_flow!
          install_step!
          install_action!
        end

        # Rules are serializable AST objects, so their arguments are always a
        # field name plus a literal — never an expression, which is what makes
        # `equals(:a, ENV["X"])` a violation.
        #
        # @return [void]
        def install_rules!
          %i[equals contains greater_than less_than].each do |name|
            allow :rule, name, positional: %i[symbol literal]
          end
          allow :rule, :not_empty, positional: %i[symbol]
          %i[all any].each { |name| allow :rule, name, positional: { repeat: :rule, min: 1 } }
        end

        # @return [void]
        def install_flow!
          allow :flow, :start, positional: %i[symbol]
          allow :flow,
            :meta,
            keywords: { title: :literal, subtitle: :literal, brand: :literal, theme: :literal }
          # FlowBuilder#allowed_domains flattens, so a literal Array is as
          # idiomatic as a list of strings; both are inert either way.
          allow :flow, :allowed_domains, positional: { repeat: :literal, min: 1 }
          allow :flow,
            :accumulator,
            positional: %i[symbol],
            keywords:   { type: :type_name, default: :literal }
          Node::VERBS.each { |verb| allow :flow, verb, positional: %i[symbol], block: :step }
          allow :flow, :action, positional: %i[symbol], keywords: { if: :rule }, block: :action
        end

        # @return [void]
        def install_step!
          allow :step, :type, positional: %i[type_name]
          allow :step, :question, positional: %i[string]
          allow :step, :text, positional: %i[string]
          allow :step, :options, positional: %i[literal]
          allow :step, :default, positional: %i[literal]
          # `required` is inert metadata: Node coerces it with `value ? true :
          # false` and serializes it as `"required": false`. It reaches nothing
          # outside the definition, and an author who can write the DSL text can
          # already delete the question outright — strictly more powerful than
          # marking it skippable — so it is allowed rather than excluded.
          # `{ optional: :literal }` mirrors `required(value = true)`: both bare
          # `required` and `required false` are real DSL.
          allow :step, :required, positional: { optional: :literal }
          allow :step, :skip_if, positional: %i[rule]
          allow :step, :transition, keywords: TRANSITION_KEYWORDS
          allow :step,
            :accumulate,
            positional: %i[symbol],
            keywords:   { lookup: :literal, per_selection: :literal, per_unit: :literal, flat: :literal }
          # widget(type:, target:, **opts) and price(**kwargs) really do take
          # open keyword lists — a widget's options and a price lookup's option
          # keys are arbitrary — so ANY_OTHER is faithful rather than lax.
          allow :step, :widget, keywords: { type: :symbol, target: :symbol, ANY_OTHER => :literal }
          allow :step,
            :price,
            keywords: { lookup: :literal, per_selection: :literal, per_unit: :literal,
                        flat: :literal, ANY_OTHER => :literal }
          exclude :step, :compute, "a compute block is arbitrary Ruby, indistinguishable from a payload"
        end

        # `text:` and `html:` are :string — not :literal — on purpose:
        # {Actions::SendEmail} also accepts `{ file: "path" }` and `File.read`s
        # it at definition time, which would turn a stored flow definition into
        # an arbitrary file-disclosure primitive with an attacker-chosen
        # recipient.
        #
        # @return [void]
        def install_action!
          allow :action,
            :send_email,
            keywords: { to: :string, from: :string, cc: :string, bcc: :string, reply_to: :string,
                        subject: :string, text: :string, html: :string, headers: :literal }
          exclude :action, :run, "a run block is arbitrary Ruby, indistinguishable from a payload"
          exclude :action,
            :webhook,
            "its destination host is authorized by the allowed_domains declared in the same " \
            "untrusted document, and plain http to localhost is permitted — configure outbound " \
            "delivery in the host application instead"
        end
      end

      reset!
    end
  end
end
