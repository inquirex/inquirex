#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 03: the top-level `send_email` verb, Liquid placeholders in
# user-facing text, and the advisory action list a completed flow hands back.
#
# Note what this script does NOT do: it never renders a template, never builds
# a message and never sends anything — and it requires no Liquid, no Markdown
# renderer and no mailer to run. The gem declares; the host renders. What you
# see printed is exactly the JSON a host would enqueue.
#
# Run:
#   bundle exec ruby examples/03_send_email_actions.rb

require "bundler/setup"
require "inquirex"
require "json"

DEFINITION = Inquirex.define id: "lead-intake", version: "1.0.0" do
  meta title: "Lead Intake", subtitle: "Tell us about your project"
  accumulator :price, type: :currency, default: 0
  start :name

  ask :name do
    type :string
    question "What is your name?"
    transition to: :email
  end

  # `{{ }}` is data the host renders at display time. `#{}` is Ruby and is
  # rejected outright by Inquirex::SafeSource — that is the whole point of
  # having the former.
  ask :email do
    type :email
    question "Thanks {{ answers.name }}, where can we reach you?"
    transition to: :scope
  end

  ask :scope do
    type :enum
    question "How complex is the work?"
    options simple: "Simple", involved: "Involved"
    price simple: 250, involved: 900
    transition to: :done
  end

  say :done do
    text "Your estimate starts at ${{ accumulators.price }}."
  end

  send_email do
    to      "{{ answers.email }}"
    from    "Qualified.At"
    subject "Thank you for filling the form"
    body_markdown <<~'TEXT'
      Dear {{ answers.name }},

      Thank you for filling out the form. Your total is
      ${{ accumulators.price | round: 2 }} minimum.

      — The team
    TEXT
  end

  send_email do
    to "owner@agentica.group"
    subject "New lead: {{ answers.name }}"
    body_markdown "**{{ answers.name }}** <{{ answers.email }}> — estimate ${{ accumulators.price }}."
  end
end

engine = Inquirex::Engine.new(DEFINITION)
engine.answer("Ada Lovelace")
engine.answer("ada@lovelace.io")
engine.answer("involved")

puts "Question as stored (raw template):"
puts "  #{DEFINITION.step(:email).question}"
puts
puts "Render context at this point — bind this in your template engine:"
puts "  #{engine.render_context}"

engine.advance # past the :done display step

puts
puts "Flow finished: #{engine.finished?}"
puts "on_complete_actions (what the host may choose to process):"
puts JSON.pretty_generate(engine.on_complete_actions)

puts
puts "Authoring warnings: #{DEFINITION.template_warnings.inspect}"

restored = Inquirex::Definition.from_json(DEFINITION.to_json)
puts "Emails after JSON round-trip: #{restored.emails.map(&:subject).inspect}"
