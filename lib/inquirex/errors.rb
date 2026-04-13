# frozen_string_literal: true

module Inquirex
  module Errors
    # Base exception for all Inquirex errors.
    class Error < StandardError; end

    # Raised when a flow definition is invalid (e.g. missing start step, unknown step reference).
    class DefinitionError < Error; end

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

    # Raised when serializing or deserializing a Definition to/from JSON fails.
    class SerializationError < Error; end
  end
end
