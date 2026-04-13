# frozen_string_literal: true

module Inquirex
  module Validation
    # No-op validator: always accepts any input.
    # Used by default when no validation adapter is configured.
    class NullAdapter < Adapter
      def validate(_node, _input)
        Result.new(valid: true)
      end
    end
  end
end
