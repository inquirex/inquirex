# frozen_string_literal: true

require "uri"

module Inquirex
  module Actions
    # Declarative webhook effect: POSTs the completed answers as a JSON
    # envelope ({"answers" => {...}}) to a statically-declared URL.
    #
    # Security posture — the URL must be auditable and its host covered by the
    # definition's allowed_domains declaration:
    #
    # - the URL is a literal string; {{field}} templates are rejected so the
    #   destination host can never depend on user input
    # - https only; plain http is permitted solely for localhost development
    # - userinfo (https://user@host/) is rejected
    # - redirects are not followed (Net::HTTP does not follow them)
    # - the host check runs in Definition#validate!, which every definition
    #   passes through — including JSON-rehydrated ones, so a tampered URL
    #   fails at load time, before anything executes
    #
    # A non-2xx response raises Errors::ActionError, which the Runner records
    # as a :failed result without blocking other actions.
    class Webhook < Base
      # Default open/read timeout in seconds for the webhook POST.
      DEFAULT_TIMEOUT = 10
      # Hosts for which plain http is tolerated (local development only).
      LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

      attr_reader :url, :headers, :timeout

      # @param url [String] literal https URL (no {{field}} templates)
      # @param headers [Hash] extra request headers (literal values)
      # @param timeout [Integer] open/read timeout in seconds
      def initialize(url:, headers: {}, timeout: DEFAULT_TIMEOUT)
        super()
        @url = url.to_s
        @headers = headers.transform_keys(&:to_s).transform_values(&:to_s).freeze
        @timeout = timeout.to_i
        @uri = parse_and_check!(@url)
        freeze
      end

      # @return [String] lowercase host of the webhook URL
      def host = @uri.host.downcase

      # POSTs the answers envelope to the declared URL.
      #
      # @param answers [Answers] completed answers
      # @param _outbox [Outbox] unused — webhooks build no messages
      # @return [Net::HTTPResponse] the 2xx response
      # @raise [Errors::ActionError] when the endpoint responds non-2xx
      def call(answers, _outbox)
        require "net/http"
        response = post(answers)
        code = response.code.to_i
        return response if (200..299).cover?(code)

        raise Errors::ActionError, "webhook #{host} responded with HTTP #{response.code}"
      end

      # Enforced from Definition#validate!.
      #
      # @param definition [Definition] owning definition, source of allowed_domains
      # @return [void]
      # @raise [Errors::DefinitionError] when the host is not allowlisted
      def validate_against(definition)
        return if definition.allowed_host?(host)

        raise Errors::DefinitionError,
          "webhook url host #{host.inspect} is not covered by allowed_domains " \
          "#{definition.allowed_domains.inspect} — declare it at the top of the definition"
      end

      # @return [Hash] wire format, same shape .from_h accepts
      def to_h
        hash = { "type" => "webhook", "url" => @url }
        hash["headers"] = @headers unless @headers.empty?
        hash["timeout"] = @timeout unless @timeout == DEFAULT_TIMEOUT
        hash
      end

      # @param hash [Hash] string or symbol keys
      # @return [Webhook]
      def self.from_h(hash)
        fetch = ->(key) { hash[key.to_s] || hash[key.to_sym] }
        new(
          url:     fetch.call(:url),
          headers: fetch.call(:headers) || {},
          timeout: fetch.call(:timeout) || DEFAULT_TIMEOUT
        )
      end

      private

      def post(answers)
        request = Net::HTTP::Post.new(@uri)
        request["Content-Type"] = "application/json"
        @headers.each { |name, value| request[name] = value }
        request.body = JSON.generate("answers" => answers.to_h)

        Net::HTTP.start(
          @uri.host,
          @uri.port,
          use_ssl:      @uri.scheme == "https",
          open_timeout: @timeout,
          read_timeout: @timeout
        ) { |http| http.request(request) }
      end

      def parse_and_check!(url)
        if url.include?("{{")
          raise Errors::DefinitionError,
            "webhook url does not support {{field}} templates — the destination must be static"
        end

        uri = parse(url)
        raise Errors::DefinitionError, "webhook url must be http(s): #{url.inspect}" unless uri.is_a?(URI::HTTP)
        raise Errors::DefinitionError, "webhook url must include a host: #{url.inspect}" if uri.host.to_s.empty?
        raise Errors::DefinitionError, "webhook url must not include userinfo: #{url.inspect}" if uri.userinfo

        if uri.scheme == "http" && !LOCAL_HOSTS.include?(uri.host.downcase)
          raise Errors::DefinitionError,
            "webhook url must use https (plain http is allowed only for localhost): #{url.inspect}"
        end

        uri
      end

      def parse(url)
        URI.parse(url)
      rescue URI::InvalidURIError => e
        raise Errors::DefinitionError, "webhook url is not a valid URL: #{e.message}"
      end
    end

    register(:webhook, Webhook)
  end
end
