# frozen_string_literal: true

module Inquirex
  module DSL
    # Builds an {Email} from a top-level `send_email` block. Every word is a
    # setter taking one template String, matching the rest of the DSL's idiom
    # (`type :string`, `question "..."`) rather than a keyword-argument hash:
    #
    #   send_email do
    #     to      "{{ answers.email }}"
    #     from    "Qualified.At"
    #     subject "Thank you for filling the form"
    #     body_markdown <<~'TEXT'
    #       Dear {{ answers.name }},
    #
    #       Your total is ${{ accumulators.price | round: 2 }} minimum.
    #     TEXT
    #   end
    #
    # There is deliberately no `body_html` and no `markdown_to_html(...)`
    # helper: the format is a property of the body, not a function call, and
    # one Markdown source yields both MIME parts. See {Email} for who renders
    # what.
    class EmailBuilder
      def initialize
        @attributes = {}
      end

      # Sets the recipient template.
      #
      # @param value [String] e.g. `"{{ answers.email }}"`
      # @return [void]
      def to(value)
        @attributes[:to] = value
      end

      # Sets the sender template. Optional — omit it to let the host apply its
      # configured default sender.
      #
      # @param value [String] e.g. `"Qualified.At <forms@qualified.at>"`
      # @return [void]
      def from(value)
        @attributes[:from] = value
      end

      # Sets the subject template.
      #
      # @param value [String]
      # @return [void]
      def subject(value)
        @attributes[:subject] = value
      end

      # Sets the Markdown body template — the single source for both the
      # `text/plain` and the `text/html` part of the message the host builds.
      #
      # @param value [String] Markdown with Liquid `{{ }}` placeholders;
      #   write it as a single-quoted heredoc (`<<~'TEXT'`)
      # @return [void]
      def body_markdown(value)
        @attributes[:body_markdown] = value
      end

      # @return [Email] the frozen declaration
      # @raise [Errors::DefinitionError] when a required field is missing
      def build
        Email.new(
          to:            @attributes[:to],
          from:          @attributes[:from],
          subject:       @attributes[:subject],
          body_markdown: @attributes[:body_markdown]
        )
      end
    end
  end
end
