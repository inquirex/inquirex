# frozen_string_literal: true

module Inquirex
  # Formats what the user actually saw into the prose entries a `:text`
  # accumulator collects.
  #
  # The Engine appends one entry per *interaction* — an answered question, a
  # skipped question, a display step advanced past — and never for a step the
  # engine elided on its own. A step removed by `skip_if`, or auto-skipped
  # because an extraction already answered it, was never on screen, so it must
  # not appear in a narrative that claims to be a record of the session.
  #
  # Entries are plain prose rather than JSON because their only consumer is an
  # LLM prompt: `Q:` / `A:` reads as dialogue to a model, where a serialized
  # answers hash reads as data and produces a summary that sounds like one.
  module Transcript
    # Shown instead of an answer for a question the user declined.
    SKIPPED = "(skipped)"

    # Shown instead of an answer when a step somehow carries none.
    NO_ANSWER = "(no answer)"

    class << self
      # The entry for a display step (say/header/btw/warning) the user has
      # just advanced past: its text, verbatim.
      #
      # @param node [Node] the display step
      # @return [String, nil] nil when the step carries no text
      def display_entry(node)
        text = node.text.to_s.strip
        text.empty? ? nil : text
      end

      # The entry for a question the user answered.
      #
      # @param node [Node] the collecting step
      # @param answer [Object] the value the user submitted
      # @return [String, nil] nil when the step carries no question text
      def answer_entry(node, answer)
        exchange(node, format_answer(answer, node))
      end

      # The entry for an optional question the user declined.
      #
      # @param node [Node] the collecting step
      # @return [String, nil] nil when the step carries no question text
      def skipped_entry(node)
        exchange(node, SKIPPED)
      end

      # Renders an answer the way it was shown, not the way it is stored:
      # option values become their labels where the step declares them, so the
      # narrative reads "Married filing jointly" rather than
      # "married_filing_jointly".
      #
      # @param answer [Object] a stored answer value
      # @param node [Node, nil] the step it belongs to, for label lookup
      # @return [String]
      def format_answer(answer, node = nil)
        case answer
        when nil        then NO_ANSWER
        when true       then "Yes"
        when false      then "No"
        when Array      then format_array(answer, node)
        else                 label_for(answer, node)
        end
      end

      private

      # @return [String, nil]
      def exchange(node, rendered)
        question = node.question.to_s.strip
        return nil if question.empty?

        "Q: #{question}\nA: #{rendered}"
      end

      # @return [String]
      def format_array(answer, node)
        return NO_ANSWER if answer.empty?

        answer.map { |entry| label_for(entry, node) }.join(", ")
      end

      # @return [String]
      def label_for(value, node)
        labels = node&.option_labels
        labels&.fetch(value.to_s, nil) || value.to_s
      end
    end
  end
end
