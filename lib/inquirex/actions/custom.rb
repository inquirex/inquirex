# frozen_string_literal: true

module Inquirex
  module Actions
    # Escape-hatch effect wrapping an arbitrary Ruby block, declared in the
    # DSL as `run { |answers, outbox| ... }`. Full language power — build a
    # Mail::Message by hand with outbox.add_message, call a service, record
    # metrics — at the cost of serialization: like every lambda in Inquirex,
    # the block is stripped from JSON and exists only in Ruby-authored
    # definitions.
    class Custom < Base
      # @param block [Proc] receives (answers, outbox)
      def initialize(block)
        super()
        @block = block
        freeze
      end

      # Invokes the wrapped block with the collected answers and the outbox.
      #
      # @param answers [Answers] completed answers
      # @param outbox [Outbox] collector for messages the block may build
      # @return [Object] whatever the block returns (recorded, not interpreted)
      def call(answers, outbox)
        @block.call(answers, outbox)
      end

      def serializable? = false
    end
  end
end
