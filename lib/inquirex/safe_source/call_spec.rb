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
    # - `block` — either `:forbidden`, or the name of the nested scope whose
    #   vocabulary the block's statements are validated against.
    #
    # Value kinds are `:literal`, `:string`, `:symbol`, `:type_name` and `:rule`.
    #
    # @example The spec behind `transition to: :next, if_rule: equals(:a, 1)`
    #   CallSpec.new(positional: [],
    #     keywords: { to: :symbol, if_rule: :rule, requires_server: :literal },
    #     block:    :forbidden)
    CallSpec = Data.define(:positional, :keywords, :block)
  end
end
