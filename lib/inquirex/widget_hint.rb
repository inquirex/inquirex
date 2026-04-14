# frozen_string_literal: true

module Inquirex
  # Immutable rendering hint attached to a step node.
  # Carries a widget type (e.g. :radio_group) and an optional options hash
  # (e.g. { columns: 2 }). Framework-agnostic — consumed by the JS widget,
  # TTY adapter, or any other frontend renderer.
  #
  # @example
  #   hint = WidgetHint.new(type: :radio_group, options: { columns: 2 })
  #   hint.to_h  # => { "type" => "radio_group", "columns" => 2 }
  WidgetHint = Data.define(:type, :options) do
    def initialize(type:, options: {})
      super(type: type.to_sym, options: options.transform_keys(&:to_sym).freeze)
    end

    # Serializes to a flat hash: type key + option keys merged in.
    #
    # @return [Hash<String, Object>]
    def to_h
      { "type" => type.to_s }.merge(options.transform_keys(&:to_s))
    end

    # Deserializes from a plain hash (string or symbol keys).
    #
    # @param hash [Hash]
    # @return [WidgetHint]
    def self.from_h(hash)
      type = hash["type"] || hash[:type]
      options = hash.reject { |k, _| k.to_s == "type" }
                    .transform_keys(&:to_sym)
      new(type:, options:)
    end
  end
end
