# frozen_string_literal: true

module Inquirex
  module DSL
    # Collects the fields of a `send_email` block. Every setter is an explicit
    # builder method — the block form mirrors the step builders (`type`,
    # `question`, ...) rather than a keyword-argument hash:
    #
    #   send_email if: not_empty(:email) do
    #     to      "{{email}}"
    #     from    "forms@agentica.group"
    #     subject "Thanks {{name}}"
    #     markdown_text <<~TEXT
    #       Hi {{name}}, we got your answers:
    #
    #       {{answers_summary}}
    #     TEXT
    #   end
    class SendEmailBuilder
      # @return [Hash{Symbol => Object}] collected SendEmail constructor params
      attr_reader :params

      def initialize
        @params = {}
      end

      # @param value [String] recipient template ({{field}} placeholders allowed)
      # @return [void]
      def to(value)
        @params[:to] = value
      end

      # @param value [String] sender template
      # @return [void]
      def from(value)
        @params[:from] = value
      end

      # @param value [String] carbon-copy template
      # @return [void]
      def cc(value)
        @params[:cc] = value
      end

      # @param value [String] blind-carbon-copy template
      # @return [void]
      def bcc(value)
        @params[:bcc] = value
      end

      # @param value [String] reply-to template
      # @return [void]
      def reply_to(value)
        @params[:reply_to] = value
      end

      # @param value [String] subject template
      # @return [void]
      def subject(value)
        @params[:subject] = value
      end

      # @param value [Hash] extra headers (values support {{field}})
      # @return [void]
      def headers(value)
        @params[:headers] = value
      end

      # @param value [String, Hash] plain-text body template or { file: "path" }
      # @return [void]
      def text(value)
        @params[:text] = value
      end

      # @param value [String, Hash] Markdown body template or { file: "path" }
      # @return [void]
      def markdown_text(value)
        @params[:markdown_text] = value
      end

      # @param value [String, Hash] HTML body template or { file: "path" }
      # @return [void]
      def html(value)
        @params[:html] = value
      end
    end
  end
end
