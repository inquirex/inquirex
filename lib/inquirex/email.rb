# frozen_string_literal: true

module Inquirex
  # An email a flow declares it wants sent when it completes, written with the
  # top-level `send_email` verb:
  #
  #   Inquirex.define do
  #     start :name
  #     # ... steps ...
  #
  #     send_email do
  #       to      "{{ answers.email }}"
  #       from    "Qualified.At"
  #       subject "Thank you for filling the form"
  #       body_markdown <<~'TEXT'
  #         Dear {{ answers.name }},
  #
  #         Thank you for filling out the form. Your total is
  #         ${{ accumulators.price | round: 2 }} minimum.
  #       TEXT
  #     end
  #   end
  #
  # ## The gem declares, the host renders
  #
  # This object holds four **opaque template strings**. It never renders them,
  # never converts Markdown, never builds a message and never delivers
  # anything. That is not an omission — the core gem has no required runtime
  # dependencies, and rendering would mean depending on a template engine, a
  # Markdown converter and a mailer. So `send_email` serializes into the wire
  # format alongside the steps, and the host application (which already has
  # Liquid, a Markdown renderer and ActionMailer) does the work:
  #
  # 1. render each field with **Liquid**, binding whatever context it exposes;
  # 2. render `text/plain` from the rendered `body_markdown` **as-is** —
  #    Markdown is designed to read as plain text, which is why there is no
  #    second body field — and `text/html` from Markdown → HTML;
  # 3. deliver.
  #
  # The division of labour mirrors how lambdas are handled everywhere else in
  # Inquirex: the definition describes the intent, the server-side host owns
  # the execution.
  #
  # ## Templating
  #
  # Placeholders are {https://shopify.github.io/liquid/ Liquid} `{{ }}`
  # expressions. Liquid was chosen over ERB or plain Ruby interpolation for one
  # reason: a stored flow definition is untrusted text, and Liquid cannot
  # execute arbitrary Ruby. Which drops (`answers`, `accumulators`, ...) are in
  # scope is the host's decision; this gem attaches no meaning to the names. The
  # conventional binding is `answers` (from {Engine#answers}) and
  # `accumulators` (from {Engine#totals}).
  #
  # Write bodies with a **single-quoted heredoc** (`<<~'TEXT'`). A plain
  # `<<~TEXT` interpolates `#{}` in Ruby before the template ever reaches
  # Liquid, which is exactly the hole {SafeSource} closes for stored DSL.
  #
  # When Liquid happens to be loaded in the process, every field is parsed at
  # definition time in strict mode so an authoring typo surfaces where the
  # author can see it. When it is not, the strings are stored verbatim and the
  # host validates on its own terms — see {.liquid_template_class}.
  class Email
    # Discriminator this declaration carries in {Engine#on_complete_actions},
    # so future action types (a webhook, a CRM push) are additive.
    ACTION_TYPE = "send_email"

    # Template fields, in declaration order. Doubles as the `to_h` key order.
    FIELDS = %i[to from subject body_markdown].freeze

    # Fields a declaration is meaningless without.
    REQUIRED_FIELDS = %i[to subject body_markdown].freeze

    # @return [String] recipient template, e.g. `"{{ answers.email }}"`
    attr_reader :to

    # @return [String, nil] sender template; nil leaves the choice to the host,
    #   which normally has a configured default sender
    attr_reader :from

    # @return [String] subject template
    attr_reader :subject

    # @return [String] Markdown body template, the single source for both the
    #   `text/plain` and the `text/html` part
    attr_reader :body_markdown

    # @param to [String] recipient template (required)
    # @param subject [String] subject template (required)
    # @param body_markdown [String] Markdown body template (required)
    # @param from [String, nil] sender template
    # @raise [Errors::DefinitionError] when a required field is blank, a field
    #   is not a String, or (with Liquid loaded) a template does not parse
    def initialize(to:, subject:, body_markdown:, from: nil)
      @to = to
      @from = from
      @subject = subject
      @body_markdown = body_markdown
      validate!
      freeze
    end

    # @return [Hash{String => String}] wire format, the same shape {.from_h}
    #   accepts; `from` is omitted when it was not declared
    def to_h
      FIELDS.each_with_object({}) do |field, hash|
        value = public_send(field)
        hash[field.to_s] = value if value
      end
    end

    # One entry of {Engine#on_complete_actions}: this declaration's raw
    # templates, tagged with {ACTION_TYPE} and carrying the context the host
    # renders them against.
    #
    # The templates are **not** rendered here — the gem has no Liquid. Pairing
    # them with a context snapshot is what makes the entry self-contained: a
    # background job can pick it up minutes later, with no engine and no
    # session, and still have everything it needs.
    #
    # @example
    #   email.to_action("answers" => { "name" => "Ada" }, "accumulators" => {})
    #   # => { "type"          => "send_email",
    #   #      "to"            => "{{ answers.email }}",
    #   #      "subject"       => "Thanks",
    #   #      "body_markdown" => "Dear {{ answers.name }},\n",
    #   #      "context"       => { "answers" => { "name" => "Ada" }, "accumulators" => {} } }
    #
    # @param context [Hash] JSON-serializable Liquid context
    # @return [Hash{String => Object}]
    def to_action(context)
      { "type" => ACTION_TYPE }.merge(to_h).merge("context" => context)
    end

    # @param hash [Hash] string or symbol keys
    # @return [Email]
    def self.from_h(hash)
      fetch = ->(key) { hash[key.to_s] || hash[key.to_sym] }
      new(
        to:            fetch.call(:to),
        from:          fetch.call(:from),
        subject:       fetch.call(:subject),
        body_markdown: fetch.call(:body_markdown)
      )
    end

    # The class used to syntax-check templates at definition time, or nil when
    # the process has no Liquid.
    #
    # Liquid is deliberately *not* a dependency of this gem — it is looked up
    # at call time so that a host which has it (every Rails app that renders
    # these emails does) gets authoring errors immediately, while a host which
    # does not still loads every definition. The seam is a method rather than
    # an inline `defined?` so both paths are testable.
    #
    # @return [Class, nil] `Liquid::Template` when Liquid is loaded
    def self.liquid_template_class
      ::Liquid::Template if defined?(::Liquid::Template)
    end

    private

    # @return [void]
    # @raise [Errors::DefinitionError]
    def validate!
      FIELDS.each do |field|
        value = public_send(field)
        next if value.nil? || value.is_a?(String)

        raise Errors::DefinitionError,
          "send_email #{field} must be a template String, got #{value.inspect}"
      end

      REQUIRED_FIELDS.each do |field|
        value = public_send(field)
        raise Errors::DefinitionError, "send_email requires #{field}" if value.nil? || value.strip.empty?
      end

      FIELDS.each { |field| check_liquid!(field, public_send(field)) }
    end

    # Parses one template with Liquid in strict mode, when Liquid is loaded.
    #
    # The rescue is `StandardError` rather than `Liquid::SyntaxError` on
    # purpose: naming that class would require the constant to exist, which is
    # the dependency this gem does not take. Any failure to parse a template is
    # an authoring error either way.
    #
    # @param field [Symbol] which template, for the message
    # @param source [String, nil] the template
    # @return [void]
    # @raise [Errors::DefinitionError] when the template does not parse
    def check_liquid!(field, source)
      template_class = self.class.liquid_template_class
      return if template_class.nil? || source.nil?

      begin
        template_class.parse(source, error_mode: :strict)
      rescue StandardError => e
        raise Errors::DefinitionError, "send_email #{field} is not valid Liquid: #{e.message}"
      end
    end
  end
end
