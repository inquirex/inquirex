# frozen_string_literal: true

module Inquirex
  # A conservative reader of the Liquid references inside a flow's user-facing
  # strings, and the authoring warnings they produce.
  #
  # ## Why Liquid at all
  #
  # Every user-facing string in the DSL — a step's `question`, a display step's
  # `text`, a `send_email` field — may carry `{{ }}` placeholders referring to
  # earlier answers and to accumulator totals:
  #
  #   ask :email do
  #     type :email
  #     question "Thanks {{ answers.name }}, where can we reach you?"
  #   end
  #
  #   say :quote do
  #     text "Your estimate is ${{ accumulators.price | round: 2 }}."
  #   end
  #
  # This is the **safe replacement** for the thing authors otherwise reach for
  # Ruby interpolation to do. `"Thanks #{answers[:name]}"` is arbitrary code
  # execution, which is why {SafeSource} rejects `#{}` outright in stored DSL;
  # `{{ }}` achieves the same result as pure data, so adding it *relieves*
  # pressure on the security boundary rather than widening it. The two are not
  # variations on a theme and must not be confused: `{{ }}` is data the host
  # renders, `#{}` is Ruby and is forbidden.
  #
  # ## What this gem does and does not do
  #
  # It stores the strings verbatim. {Node#question}, {Node#text} and the
  # {Email} fields all return the raw source, and rendering happens in the host
  # — at **display time**, against {Engine#render_context}, because answers
  # accumulate as the wizard progresses and a question shown at step 4 may
  # reference an answer collected at step 2.
  #
  # ## What this module adds
  #
  # A cheap, dependency-free scan for `{{ answers.X }}` and
  # `{{ accumulators.Y }}` references, so a reference to a field no step
  # collects is caught while authoring instead of rendering blank in front of a
  # lead. It is deliberately a **warning**, not an error, and deliberately
  # partial: full Liquid syntax cannot be parsed without Liquid, so anything
  # this regexp does not recognize is passed over in silence rather than
  # rejected on a guess.
  #
  # @example
  #   Inquirex::TemplateRefs.scan("Hi {{ answers.name }}, you owe {{ accumulators.price }}")
  #   # => [[:answers, :name], [:accumulators, :price]]
  #
  #   definition.template_warnings
  #   # => ["step :email question references {{ answers.phone }}, which no step collects"]
  module TemplateRefs
    # Matches the opening of a `{{ answers.field }}` / `{{ accumulators.name }}`
    # reference: capture 1 is the drop, capture 2 the first path segment (the
    # answer key or accumulator name). Deliberately does not try to parse the
    # rest of the expression — filters, nested paths and whitespace control are
    # Liquid's business.
    REFERENCE = /\{\{-?\s*(answers|accumulators)\.([A-Za-z_]\w*)/

    # Answer keys {Engine#answers_with_metadata} merges in, which no step
    # collects but a template may legitimately reference.
    RESERVED_ANSWER_KEYS = %i[completion_metadata skipped].freeze

    module_function

    # @param source [String, nil] a user-facing DSL string
    # @return [Boolean] whether it contains anything Liquid would render
    def template?(source)
      source.to_s.include?("{{") || source.to_s.include?("{%")
    end

    # Every `answers.` / `accumulators.` reference the string makes.
    #
    # @param source [String, nil] a user-facing DSL string
    # @return [Array<Array(Symbol, Symbol)>] `[drop, name]` pairs, in order of
    #   appearance, duplicates removed
    def scan(source)
      source.to_s.scan(REFERENCE).map { |drop, name| [drop.to_sym, name.to_sym] }.uniq
    end

    # Warnings for every reference in the definition that resolves to nothing:
    # an `answers.` key no step collects, or an `accumulators.` name the flow
    # never declared.
    #
    # @param definition [Definition]
    # @return [Array<String>] empty when every reference resolves
    def warnings(definition)
      known_answers = definition.step_ids + RESERVED_ANSWER_KEYS
      known_totals = definition.accumulators.keys

      strings(definition).flat_map do |label, source|
        scan(source).filter_map do |drop, name|
          known = drop == :answers ? known_answers : known_totals
          next if known.include?(name)

          "#{label} references {{ #{drop}.#{name} }}, " \
            "which #{drop == :answers ? "no step collects" : "is not a declared accumulator"}"
        end
      end
    end

    # Every user-facing string in the definition, paired with a label naming
    # where it came from.
    #
    # @param definition [Definition]
    # @return [Array<Array(String, String)>] `[label, source]` pairs
    def strings(definition)
      from_steps(definition) + from_emails(definition)
    end

    # @param definition [Definition]
    # @return [Array<Array(String, String)>]
    def from_steps(definition)
      definition.steps.flat_map do |step_id, node|
        [["step #{step_id.inspect} question", node.question],
         ["step #{step_id.inspect} text", node.text]].select { |_label, source| source }
      end
    end

    # @param definition [Definition]
    # @return [Array<Array(String, String)>]
    def from_emails(definition)
      definition.emails.each_with_index.flat_map do |email, index|
        Email::FIELDS.filter_map do |field|
          value = email.public_send(field)
          ["send_email ##{index + 1} #{field}", value] if value
        end
      end
    end
  end
end
