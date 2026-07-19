# frozen_string_literal: true

module Inquirex
  module Actions
    # Collected output of running a definition's actions: the Mail::Message
    # objects built by send_email effects, plus a per-execution result trail.
    #
    # The outbox is attached to Answers#outbox and is intentionally excluded
    # from Answers serialization — mail objects never leak into persisted
    # answer data. Delivery is the host application's job:
    #
    #   answers.outbox.each do |message|
    #     ActionMailer::Base.wrap_delivery_behavior(message)
    #     message.deliver
    #   end
    class Outbox
      include Enumerable

      # One entry per effect execution (or per skipped action).
      # status is :ok, :skipped (action rule was false), or :failed.
      Result = Data.define(:action_id, :status, :error)

      attr_reader :messages, :results

      def initialize
        @messages = []
        @results = []
      end

      # @param mail [Mail::Message]
      # @return [Mail::Message]
      def add_message(mail)
        @messages << mail
        mail
      end

      # @param action_id [Symbol]
      # @param status [Symbol] :ok, :skipped, or :failed
      # @param error [StandardError, nil]
      def record(action_id, status, error: nil)
        @results << Result.new(action_id:, status:, error:)
      end

      # Iterates over built Mail::Message objects.
      def each(&) = @messages.each(&)

      # @return [Integer] number of built messages
      def size = @messages.size

      # @return [Boolean]
      def empty? = @messages.empty?

      # @return [Array<Result>] executions that raised
      def failures = @results.select { |result| result.status == :failed }
    end
  end
end
