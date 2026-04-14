# frozen_string_literal: true

module Inquirex
  # Canonical mapping from Inquirex data types to default widget types per rendering context.
  #
  # Desktop defaults lean toward richer controls (radio groups, checkbox groups).
  # Mobile defaults lean toward compact controls (dropdowns, toggles).
  # TTY defaults align with tty-prompt methods.
  #
  # Adapters (TTY, JS, Rails) use this to pick an appropriate renderer when
  # the DSL author has not specified an explicit `widget` hint.
  module WidgetRegistry
    WIDGET_TYPES = %i[
      text_input
      textarea
      number_input
      currency_input
      toggle
      yes_no_buttons
      yes_no
      radio_group
      dropdown
      checkbox_group
      multi_select_dropdown
      select
      multi_select
      enum_select
      multiline
      mask
      slider
      date_picker
      email_input
      phone_input
    ].freeze

    # Default widget per data type and rendering context.
    DEFAULTS = {
      string:     { desktop: :text_input,    mobile: :text_input,     tty: :text_input },
      text:       { desktop: :textarea,      mobile: :textarea,       tty: :multiline },
      integer:    { desktop: :number_input,  mobile: :number_input,   tty: :number_input },
      decimal:    { desktop: :number_input,  mobile: :number_input,   tty: :number_input },
      currency:   { desktop: :currency_input, mobile: :currency_input, tty: :number_input },
      boolean:    { desktop: :toggle,        mobile: :yes_no_buttons, tty: :yes_no },
      enum:       { desktop: :radio_group,   mobile: :dropdown,       tty: :select },
      multi_enum: { desktop: :checkbox_group, mobile: :checkbox_group, tty: :multi_select },
      date:       { desktop: :date_picker,   mobile: :date_picker,    tty: :text_input },
      email:      { desktop: :email_input,   mobile: :email_input,    tty: :text_input },
      phone:      { desktop: :phone_input,   mobile: :phone_input,    tty: :text_input }
    }.freeze

    # Returns the default widget type for a given data type and context.
    #
    # @param type [Symbol, String, nil] Inquirex data type (e.g. :enum, :integer)
    # @param context [Symbol] :desktop, :mobile, or :tty (default: :desktop)
    # @return [Symbol, nil] widget type symbol, or nil if type is unknown
    def self.default_for(type, context: :desktop)
      DEFAULTS.dig(type&.to_sym, context)
    end

    # Returns a WidgetHint with the default widget for the given type + context,
    # or nil when no default exists (e.g. for display verbs with no type).
    #
    # @param type [Symbol, String, nil]
    # @param context [Symbol]
    # @return [WidgetHint, nil]
    def self.default_hint_for(type, context: :desktop)
      widget_type = default_for(type, context:)
      widget_type ? WidgetHint.new(type: widget_type) : nil
    end
  end
end
