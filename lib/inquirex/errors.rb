# frozen_string_literal: true

module Inquirex
  # Namespace for all Inquirex exception classes.
  module Errors
    # Base exception for all Inquirex errors.
    class Error < StandardError; end

    # Raised when a flow definition is invalid (e.g. missing start step, unknown step reference).
    class DefinitionError < Error; end

    # Raised when DSL source contains anything outside the flow-DSL allowlist,
    # i.e. when it is not safe to `eval`. See Inquirex::SafeSource.
    #
    # Subclasses DefinitionError on purpose: hosts that already rescue that
    # class and render the message keep working, and a rejected payload reads
    # as "invalid DSL" rather than as a crash.
    class UnsafeSourceError < DefinitionError
      # @return [Array<String>] every violation found, most useful first
      attr_reader :violations

      # @param violations [Array<String>, String] human-readable violation messages
      def initialize(violations)
        @violations = Array(violations)
        super("DSL rejected: #{@violations.join("; ")}")
      end
    end

    # Raised when navigating to or requesting a step id not found in the definition.
    class UnknownStepError < Error; end

    # Base exception for runtime engine errors.
    class EngineError < Error; end

    # Raised when Engine#answer is called after the flow has already finished.
    class AlreadyFinishedError < EngineError; end

    # Raised when the validator rejects the user's answer for the current step.
    class ValidationError < EngineError; end

    # Raised when Engine#answer is called on a non-collecting step (say/header/btw/warning).
    # Use Engine#advance for non-collecting steps.
    class NonCollectingStepError < EngineError; end

    # Raised when Engine#skip is called on a step that is required (the default).
    # Only steps declared with `required false` may be skipped by the user.
    class RequiredStepError < EngineError; end

    # Raised when serializing or deserializing a Definition to/from JSON fails.
    class SerializationError < Error; end

    # Raised when a post-completion action cannot execute structurally,
    # e.g. send_email is used without the mail gem installed.
    class ActionError < Error; end
  end
end
