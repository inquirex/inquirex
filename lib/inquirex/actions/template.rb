# frozen_string_literal: true

require "cgi/escape"

module Inquirex
  module Actions
    # Renders {{field}} placeholders against collected answers.
    #
    # Placeholders are dot-notation keys resolved via Answers#to_flat_h
    # ("{{email}}", "{{business.count}}"). The syntax is deliberately inert —
    # no code execution — so flow definitions stored in a database can be
    # rendered server-side safely and a visual editor can preview templates
    # client-side. It matches the {{field}} placeholder convention used by
    # inquirex-llm prompts.
    #
    # Rendering modes:
    # - render_text — values inserted verbatim
    # - render_html — every interpolated value is HTML-escaped
    #
    # The built-in {{answers_summary}} placeholder expands to all collected
    # answers: "key: value" lines in text mode, a simple table in HTML mode.
    # Unknown fields render as empty strings; array values join with ", ".
    module Template
      PLACEHOLDER = /\{\{\s*([\w.]+)\s*\}\}/
      SUMMARY_KEY = "answers_summary"

      module_function

      # @param string [String] template with {{field}} placeholders
      # @param answers [Answers]
      # @return [String]
      def render_text(string, answers)
        render(string, answers, html: false)
      end

      # @param string [String] template with {{field}} placeholders
      # @param answers [Answers]
      # @return [String]
      def render_html(string, answers)
        render(string, answers, html: true)
      end

      def render(string, answers, html:)
        flat = answers.to_flat_h
        string.gsub(PLACEHOLDER) do
          key = Regexp.last_match(1)
          next(html ? summary_html(flat) : summary_text(flat)) if key == SUMMARY_KEY

          value = format_value(flat[key])
          html ? CGI.escapeHTML(value) : value
        end
      end

      def format_value(value)
        value.is_a?(Array) ? value.join(", ") : value.to_s
      end

      def summary_text(flat)
        flat.map { |key, value| "#{key}: #{format_value(value)}" }.join("\n")
      end

      def summary_html(flat)
        rows = flat.map do |key, value|
          "<tr><th>#{CGI.escapeHTML(key)}</th><td>#{CGI.escapeHTML(format_value(value))}</td></tr>"
        end
        %(<table class="inquirex-answers">#{rows.join}</table>)
      end
    end
  end
end
