# frozen_string_literal: true

module Inquirex
  module Actions
    # Declarative email effect. Builds a Mail::Message (the object ActionMailer
    # itself wraps) from {{field}} templates and appends it to the outbox.
    # Nothing is delivered — the host application sends the messages.
    #
    # Scalar fields (to, from, cc, bcc, reply_to, subject) and the text body
    # render values verbatim; the html body HTML-escapes every interpolated
    # value automatically. Both bodies given => multipart/alternative.
    #
    # Bodies must be inline template Strings. The `{ file: "path" }` form was
    # removed in 0.7.0: the gem `File.read` it at definition time, which turned
    # a stored flow definition into an arbitrary file-disclosure primitive with
    # an attacker-chosen recipient.
    #
    # Images: reference external URLs in the html body. Attachments are
    # deliberately unsupported.
    #
    # The mail gem is a soft dependency, required only when a message is
    # actually built. Rails hosts always have it (ActionMailer depends on it).
    #
    # @deprecated Along with the whole `action` verb. The top-level
    #   `send_email` block ({Email}) replaces it: the gem declares the
    #   templates and the host renders and delivers, so the core gem needs
    #   neither the mail gem nor a template engine. See {DSL::FlowBuilder#action}.
    class SendEmail < Base
      # Scalar header fields rendered verbatim via Template.render_text in #to_mail and #to_h.
      SCALAR_FIELDS = %i[to from cc bcc reply_to subject].freeze

      # @return [String] required recipient / subject templates ({{field}} placeholders allowed)
      attr_reader :to, :subject

      # @return [String, nil] optional address templates ({{field}} placeholders allowed)
      attr_reader :from, :cc, :bcc, :reply_to

      # @return [String, nil] body template, inlined at definition time when { file: } was given
      attr_reader :text, :html

      # @return [Hash{String => String}] extra headers (values support {{field}})
      attr_reader :headers

      # @param to [String] recipient template (required)
      # @param subject [String] subject template (required)
      # @param text [String, nil] plain-text body template
      # @param html [String, nil] HTML body template
      # @param headers [Hash] extra headers (values support {{field}})
      # @raise [Errors::DefinitionError] when required fields are missing
      def initialize(to:, subject:, from: nil, cc: nil, bcc: nil, reply_to: nil,
        text: nil, html: nil, headers: {})
        super()
        @to = to
        @from = from
        @cc = cc
        @bcc = bcc
        @reply_to = reply_to
        @subject = subject
        @text = resolve_body(text)
        @html = resolve_body(html)
        @headers = headers.transform_keys(&:to_s).freeze
        validate!
        freeze
      end

      # Builds the message and appends it to the outbox.
      #
      # @param answers [Answers] completed answers
      # @param outbox [Outbox] receives the built Mail::Message
      # @return [void]
      def call(answers, outbox)
        outbox.add_message(to_mail(answers))
      end

      # Builds a Mail::Message from the templates and the given answers.
      # Pure function — safe to call from a background job to rebuild
      # messages from persisted answers.
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
        hash = { "type" => "send_email" }
        SCALAR_FIELDS.each do |field|
          value = public_send(field)
          hash[field.to_s] = value if value
        end
        hash["text"] = @text if @text
        hash["html"] = @html if @html
        hash["headers"] = @headers unless @headers.empty?
        hash
      end

      # @param hash [Hash] string or symbol keys
      # @return [SendEmail]
      def self.from_h(hash)
        fetch = ->(key) { hash[key.to_s] || hash[key.to_sym] }
        new(
          to:       fetch.call(:to),
          from:     fetch.call(:from),
          cc:       fetch.call(:cc),
          bcc:      fetch.call(:bcc),
          reply_to: fetch.call(:reply_to),
          subject:  fetch.call(:subject),
          text:     fetch.call(:text),
          html:     fetch.call(:html),
          headers:  fetch.call(:headers) || {}
        )
      end

      private

      def attach_bodies(mail, answers)
        text = @text && Template.render_text(@text, answers)
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

      # Bodies are inline template strings and nothing else.
      def resolve_body(value)
        return value if value.nil? || value.is_a?(String)

        raise Errors::DefinitionError,
          "send_email body must be a template String, got #{value.inspect}"
      end

      def validate!
        raise Errors::DefinitionError, "send_email requires to:" if blank?(@to)
        raise Errors::DefinitionError, "send_email requires subject:" if blank?(@subject)
        return unless @text.nil? && @html.nil?

        raise Errors::DefinitionError, "send_email requires a text: or html: body"
      end

      def blank?(value) = value.nil? || value.to_s.strip.empty?

      def require_mail!
        return if defined?(::Mail)

        require "mail"
      rescue LoadError
        raise Errors::ActionError,
          "send_email requires the mail gem — add `gem \"mail\"` to your Gemfile " \
          "(Rails applications already have it via ActionMailer)"
      end
    end

    register(:send_email, SendEmail)
  end
end
