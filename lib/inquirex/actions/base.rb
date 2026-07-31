# frozen_string_literal: true

module Inquirex
  module Actions
    # Abstract base for action effects — the executable units inside an
    # `action` block. Subclasses implement #call plus #to_h / .from_h,
    # following the same round-trip pattern as Rules::Base.
    #
    # Every effect is serializable. The two that were not — `run`, which
    # wrapped an arbitrary Ruby proc, and `webhook`, whose destination host was
    # authorized by the same untrusted document that named it — were removed in
    # 0.7.0.
    #
    # @deprecated Along with the whole `action` verb; see {DSL::FlowBuilder#action}.
    class Base
      # Executes the effect, appending anything it builds to the outbox.
      #
      # @param answers [Answers] completed answers
      # @param outbox [Outbox] collector for built messages
      # @return [void]
      def call(answers, outbox)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      # @return [Hash]
      def to_h
        raise NotImplementedError, "#{self.class}#to_h must be implemented"
      end
    end
  end
end
