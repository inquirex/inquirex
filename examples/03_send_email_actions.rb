#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 03: Post-completion actions building emails into the outbox.
#
# The `action` verb runs server-side after the flow finishes. send_email
# builds Mail::Message objects — nothing is delivered here; a host Rails app
# would iterate answers.outbox and deliver via its own ActionMailer config.
#
# Run:
#   bundle exec ruby examples/03_send_email_actions.rb

require "bundler/setup"
require "inquirex"

DEFINITION = Inquirex.define id: "lead-intake", version: "1.0.0" do
  meta title: "Lead Intake", subtitle: "Tell us about your project"
  start :name

  ask :name do
    type :string
    question "What is your name?"
    transition to: :email
  end

  ask :email do
    type :email
    question "Where can we reach you? (leave blank to skip the receipt)"
    transition to: :budget
  end

  ask :budget do
    type :currency
    question "What is your approximate budget?"
  end

  # Sent only when the visitor left an email address.
  action :client_receipt, if: not_empty(:email) do
    send_email to:      "{{email}}",
      from:    "forms@agentica.group",
      subject: "Thanks {{name}} — we got your inquiry",
      text:    <<~TEXT,
        Hi {{name}},

        We received your answers and will reply within one business day.

        {{answers_summary}}
      TEXT
      html:    <<~HTML
        <p>Hi {{name}},</p>
        <p>We received your answers and will reply within one business day.</p>
        {{answers_summary}}
      HTML
  end

  # Always notify the site owner, and demonstrate the Ruby escape hatch.
  action :admin_alert do
    send_email to: "owner@agentica.group",
      from: "forms@agentica.group",
      subject: "New lead: {{name}} (budget {{budget}})",
      html: "{{answers_summary}}"
    run { |answers, _outbox| puts ">> run{} saw budget: #{answers.budget}" }
  end
end

answers = Inquirex::Actions.run(
  DEFINITION,
  name:   "Ada Lovelace",
  email:  "ada@lovelace.io",
  budget: 12_500.00
)

puts "Built #{answers.outbox.size} message(s):"
answers.outbox.each do |mail|
  puts "-" * 60
  puts "To:      #{mail.to.join(", ")}"
  puts "Subject: #{mail.subject}"
  puts "Parts:   #{mail.multipart? ? "text + html" : mail.content_type}"
end

puts "-" * 60
puts "Results: #{answers.outbox.results.map { |r| "#{r.action_id}=#{r.status}" }.join(", ")}"

# The definition (rules and all) round-trips through JSON — run{} is stripped:
restored = Inquirex::Definition.from_json(DEFINITION.to_json)
puts "Actions after JSON round-trip: #{restored.actions.map(&:id).inspect}"
