# frozen_string_literal: true

require "prism"

require_relative "safe_source/call_spec"
require_relative "safe_source/vocabulary"
require_relative "safe_source/validator"

module Inquirex
  # Decides whether a string of flow DSL is safe to evaluate — *without*
  # evaluating it.
  #
  # {Inquirex.load_dsl} is an `eval`. Whenever the text comes from somewhere
  # other than your own repository — a database column a customer edits, an
  # upload, an LLM, a visual builder's "sync" button — evaluating it unguarded
  # is arbitrary code execution in the process that loads the flow. Since 0.7.0
  # `load_dsl` therefore runs {SafeSource.validate!} first, and only source that
  # matches the real DSL vocabulary ({Vocabulary}) with literal arguments gets
  # past it.
  #
  # Use {.validate} or {.safe?} directly to audit stored definitions without
  # loading them — the answer is "would `load_dsl` accept this?", which is
  # exactly what you want before a deploy tightens the allowlist.
  #
  # @example Reject before evaluating
  #   Inquirex.load_dsl(customer.flow_dsl)          # validates, then evals
  #   Inquirex.load_dsl(File.read("flow.rb"), unsafe: true)  # your own file: skip validation
  #
  # @example Audit a table of stored definitions
  #   Qualifier.find_each do |q|
  #     violations = Inquirex::SafeSource.validate(q.flow_dsl)
  #     puts "REJECT #{q.id}: #{violations.join("; ")}" if violations.any?
  #   end
  #
  # @example Raise the ceilings for an unusually large questionnaire
  #   Inquirex::SafeSource.max_source_bytes = 256 * 1024
  #   Inquirex::SafeSource.max_depth = 32
  module SafeSource
    # Default ceiling on DSL source size, in bytes.
    #
    # Real flows are tiny: the largest definition anywhere in this project or
    # its downstream app — a 47-step loan application with three levels of
    # composed rules — is under 6 KB. 64 KiB is an order of magnitude above
    # that, comfortably fits a several-hundred-step questionnaire, and still
    # bounds the work handed to Prism (and to any formatter the host runs on
    # the same text), neither of which should be fed megabytes of hostile input.
    DEFAULT_MAX_SOURCE_BYTES = 64 * 1024

    # Default ceiling on AST nesting depth.
    #
    # Measured against every flow in this gem's specs and examples and the
    # downstream app's fixtures, the deepest legitimate construct needs 9 levels
    # (`define` → block → `ask` → block → `transition` → `all` → `any` →
    # `equals` → literal). 24 leaves better than 2.5x headroom while keeping
    # the validator's own recursion clear of a stack overflow triggered by
    # `all(all(all(...)))` nested a million deep.
    DEFAULT_MAX_DEPTH = 24

    @max_source_bytes = DEFAULT_MAX_SOURCE_BYTES
    @max_depth = DEFAULT_MAX_DEPTH

    class << self
      # Ceiling on DSL source size in bytes, applied by {.validate} and
      # therefore by {Inquirex.load_dsl}.
      #
      # @return [Integer]
      attr_accessor :max_source_bytes

      # Ceiling on AST nesting depth, applied by {.validate} and therefore by
      # {Inquirex.load_dsl}.
      #
      # @return [Integer]
      attr_accessor :max_depth

      # Every reason the source would be rejected. An empty array means the
      # source is inside the allowlist — it says nothing about whether the flow
      # is semantically valid (unknown step reference, missing `start`), which
      # only evaluation can decide.
      #
      # @param source [String, nil] Inquirex DSL source
      # @param max_bytes [Integer] override the size ceiling for this call
      # @param max_depth [Integer] override the depth ceiling for this call
      # @return [Array<String>] `"line N: reason"` messages, empty when safe
      def validate(source, max_bytes: max_source_bytes, max_depth: self.max_depth)
        Validator.new(source, max_bytes:, max_depth:).violations
      end

      # @param source [String, nil] Inquirex DSL source
      # @param max_bytes [Integer] override the size ceiling for this call
      # @param max_depth [Integer] override the depth ceiling for this call
      # @return [Boolean] true when the source is inside the allowlist
      def safe?(source, max_bytes: max_source_bytes, max_depth: self.max_depth)
        validate(source, max_bytes:, max_depth:).empty?
      end

      # Validates, and raises unless the source is inside the allowlist.
      #
      # @param source [String, nil] Inquirex DSL source
      # @param max_bytes [Integer] override the size ceiling for this call
      # @param max_depth [Integer] override the depth ceiling for this call
      # @return [String] the source, unchanged, when it is safe
      # @raise [Errors::UnsafeSourceError] listing every violation found
      def validate!(source, max_bytes: max_source_bytes, max_depth: self.max_depth)
        violations = validate(source, max_bytes:, max_depth:)
        raise Errors::UnsafeSourceError, violations unless violations.empty?

        source
      end
    end
  end
end
