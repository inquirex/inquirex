# frozen_string_literal: true

module Inquirex
  # A declarative email built from the collected answers, declared at flow
  # level with the DSL verb `send_email`. This is the only server-side
  # completion declaration the core gem carries — anything richer (webhooks,
  # CRM pushes, custom code) belongs to the host application.
  #
  #   send_email if: not_empty(:email) do
  #     to      "{{email}}"
  #     from    "forms@agentica.group"
  #     subject "Thanks {{name}} — we got your inquiry"
  #     markdown_text <<~TEXT
  #       Hi {{name}},
  #
  #       We received your answers and will reply within one business day.
  #
  #       {{answers_summary}}
  #     TEXT
  #   end
  #
  # Nothing is ever delivered by this gem. A SendEmail is data: templated
  # header fields plus one or more body templates, serialized into the
  # definition JSON under "send_emails". The host application decides when
  # (and whether) to render and deliver — either from the serialized fields
  # directly, or via #to_mail, which builds a Mail::Message (the object
  # ActionMailer wraps).
  #
  # Scalar fields (to, from, cc, bcc, reply_to, subject) and the text /
  # markdown_text bodies render {{field}} values verbatim; the html body
  # HTML-escapes every interpolated value automatically. markdown_text is
  # carried on the wire as markdown — the core gem never renders Markdown
  # to HTML (no dependencies); hosts that want an HTML part render it
  # themselves.
  #
  # Bodies accept an inline template String or { file: "path" }, which is
  # read once at definition time and inlined — a definition rehydrated from
  # JSON never touches the filesystem.
  #
  # The mail gem is a soft dependency, required only when #to_mail is
  # called. Rails hosts always have it (ActionMailer depends on it).
  class SendEmail
    # Scalar header fields rendered verbatim via Template.render_text in #to_mail and #to_h.
    SCALAR_FIELDS = %i[to from cc bcc reply_to subject].freeze

    # @return [String] required recipient / subject templates ({{field}} placeholders allowed)
    attr_reader :to, :subject

    # @return [String, nil] optional address templates ({{field}} placeholders allowed)
    attr_reader :from, :cc, :bcc, :reply_to

    # @return [String, nil] body template, inlined at definition time when { file: } was given
    attr_reader :text, :markdown_text, :html

    # @return [Hash{String => String}] extra headers (values support {{field}})
    attr_reader :headers

    # @return [Rules::Base, nil] gate — the email applies only when the rule is true
    attr_reader :rule

    # @param to [String] recipient template (required; keyword defaults to nil
    #   so a missing field raises the friendly DefinitionError from #validate!)
    # @param subject [String] subject template (required)
    # @param text [String, Hash, nil] plain-text body template or { file: }
    # @param markdown_text [String, Hash, nil] Markdown body template or { file: }
    # @param html [String, Hash, nil] HTML body template or { file: }
    # @param headers [Hash] extra headers (values support {{field}})
    # @param rule [Rules::Base, nil] serializable gate (the DSL's if: option)
    # @raise [Errors::DefinitionError] when required fields are missing
    def initialize(to: nil, subject: nil, from: nil, cc: nil, bcc: nil, reply_to: nil,
      text: nil, markdown_text: nil, html: nil, headers: {}, rule: nil)
      @to = to
      @from = from
      @cc = cc
      @bcc = bcc
      @reply_to = reply_to
      @subject = subject
      @text = resolve_body(text)
      @markdown_text = resolve_body(markdown_text)
      @html = resolve_body(html)
      @headers = headers.transform_keys(&:to_s).freeze
      @rule = rule
      validate!
      freeze
    end

    # Whether this email should be built for the given answers — true when
    # no gate was declared or the gate rule evaluates to true.
    #
    # @param answers_hash [Hash] step_id => value context for rule evaluation
    # @return [Boolean]
    def applicable?(answers_hash)
      @rule.nil? || @rule.evaluate(answers_hash)
    end

    # Builds a Mail::Message from the templates and the given answers.
    # Pure function — safe to call from a background job to rebuild
    # messages from persisted answers. The text part is @text, falling back
    # to @markdown_text rendered verbatim (Markdown reads fine as plain
    # text); the html part is @html when present.
    #
    # @param answers [Answers]
    # @return [Mail::Message]
    def to_mail(answers)
      require_mail!
      mail = ::Mail.new
      SCALAR_FIELDS.each do |field|
        value = public_send(field)
        mail.public_send(:"#{field}=", Template.render_text(value, answers)) if value
      end
      @headers.each { |name, value| mail.header[name] = Template.render_text(value.to_s, answers) }
      attach_bodies(mail, answers)
      mail
    end

    # @return [Hash] wire format, same shape .from_h accepts
    def to_h
      hash = {}
      hash["if"] = @rule.to_h if @rule
      SCALAR_FIELDS.each do |field|
        value = public_send(field)
        hash[field.to_s] = value if value
      end
      hash["text"] = @text if @text
      hash["markdown_text"] = @markdown_text if @markdown_text
      hash["html"] = @html if @html
      hash["headers"] = @headers unless @headers.empty?
      hash
    end

    # @param hash [Hash] string or symbol keys
    # @return [SendEmail]
    def self.from_h(hash)
      fetch = ->(key) { hash[key.to_s] || hash[key.to_sym] }
      rule_data = fetch.call(:if)
      new(
        to:            fetch.call(:to),
        from:          fetch.call(:from),
        cc:            fetch.call(:cc),
        bcc:           fetch.call(:bcc),
        reply_to:      fetch.call(:reply_to),
        subject:       fetch.call(:subject),
        text:          fetch.call(:text),
        markdown_text: fetch.call(:markdown_text),
        html:          fetch.call(:html),
        headers:       fetch.call(:headers) || {},
        rule:          rule_data ? Rules::Base.from_h(rule_data) : nil
      )
    end

    private

    def attach_bodies(mail, answers)
      text_source = @text || @markdown_text
      text = text_source && Template.render_text(text_source, answers)
      html = @html && Template.render_html(@html, answers)
      if text && html
        mail.text_part = build_part("text/plain; charset=UTF-8", text)
        mail.html_part = build_part("text/html; charset=UTF-8", html)
      elsif html
        mail.content_type = "text/html; charset=UTF-8"
        mail.body = html
      else
        mail.body = text
      end
    end

    def build_part(content_type, body)
      part = ::Mail::Part.new
      part.content_type = content_type
      part.body = body
      part
    end

    # Inline template string, or { file: "path" } read once at definition time.
    def resolve_body(value)
      return value if value.nil? || value.is_a?(String)

      path = value.is_a?(Hash) && (value[:file] || value["file"])
      return File.read(File.expand_path(path)) if path.is_a?(String)

      raise Errors::DefinitionError,
        "send_email body must be a template String or { file: \"path\" }, got #{value.inspect}"
    end

    def validate!
      raise Errors::DefinitionError, "send_email requires to:" if blank?(@to)
      raise Errors::DefinitionError, "send_email requires subject:" if blank?(@subject)
      return unless @text.nil? && @markdown_text.nil? && @html.nil?

      raise Errors::DefinitionError, "send_email requires a text:, markdown_text: or html: body"
    end

    def blank?(value) = value.nil? || value.to_s.strip.empty?

    def require_mail!
      return if defined?(::Mail)

      require "mail"
    rescue LoadError
      raise Errors::SendEmailError,
        "send_email requires the mail gem — add `gem \"mail\"` to your Gemfile " \
        "(Rails applications already have it via ActionMailer)"
    end
  end
end
