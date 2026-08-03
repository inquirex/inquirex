# frozen_string_literal: true

module Inquirex
  module SafeSource
    # The shape a single allowlisted DSL call may take, built by
    # {Vocabulary.allow} and consumed by {Validator}. Its three members:
    #
    # - `positional` — accepted positional arguments. An Array names each slot's
    #   kind in order (`[:symbol]`); `{ repeat: kind, min: n }` accepts any
    #   number of arguments of one kind; `{ optional: kind }` accepts zero or one.
    # - `keywords` — `nil` when the call takes no keyword arguments, or a Hash
    #   mapping each accepted keyword to its value kind. The key
    #   {Vocabulary::ANY_OTHER} sets the kind for every keyword not named
    #   explicitly, and is only legitimate when the real method takes `**rest`.
    # - `block` — `:forbidden`; the name of the nested scope whose vocabulary
    #   the block's statements are validated against; or `{ optional: scope }`
    #   for a call that accepts that block but does not require it, mirroring
    #   the `positional` spelling. `send_email` is the optional case: it takes
    #   its fields either as keywords or from a block.
    #
    # Value kinds are `:literal`, `:string`, `:symbol`, `:type_name` and `:rule`.
    #
    # @example The spec behind `transition to: :next, if_rule: equals(:a, 1)`
    #   CallSpec.new(positional: [],
    #     keywords: { to: :symbol, if_rule: :rule, requires_server: :literal },
    #     block:    :forbidden)
    CallSpec = Data.define(:positional, :keywords, :block) do
      # The scope this call's block opens, with `{ optional: scope }`
      # unwrapped, or nil when the call takes no block at all. Callers that
      # care whether the block is required read {#block} itself.
      #
      # @return [Symbol, nil]
      def block_scope
        case block
        when :forbidden then nil
        when Hash       then block[:optional]
        else block
        end
      end
    end
  end
end
