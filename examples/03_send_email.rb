#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 03: Completion emails declared with the top-level `send_email` verb.
#
# A send_email declaration is data, not behavior: templated header fields and
# bodies serialized into the definition JSON. Nothing is delivered here — the
# host application (qualified.at) selects the applicable declarations and
# delivers them however it likes; #to_mail builds a Mail::Message on demand.
#
# Run:
#   bundle exec ruby examples/03_send_email.rb

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
  send_email if: not_empty(:email) do
    to      "{{email}}"
    from    "forms@agentica.group"
    subject "Thanks {{name}} — we got your inquiry"
    markdown_text <<~TEXT
      Hi {{name}},

      We received your answers and will reply within one business day.

      {{answers_summary}}
    TEXT
  end

  # Always notify the site owner — inline keyword form.
  send_email to: "owner@agentica.group",
    from:    "forms@agentica.group",
    subject: "New lead: {{name}} (budget {{budget}})",
    html:    "{{answers_summary}}"
end

answers = Inquirex::Answers.new(
  name:   "Ada Lovelace",
  email:  "ada@lovelace.io",
  budget: 12_500.00
)

applicable = DEFINITION.send_emails.select { |email| email.applicable?(answers.to_h) }
puts "Applicable declarations: #{applicable.size} of #{DEFINITION.send_emails.size}"

applicable.each do |declaration|
  mail = declaration.to_mail(answers)
  puts "-" * 60
  puts "To:      #{mail.to.join(", ")}"
  puts "Subject: #{mail.subject}"
  puts "Parts:   #{mail.multipart? ? "text + html" : (mail.content_type || "text/plain")}"
end

# The definition (gate rules and all) round-trips through JSON:
restored = Inquirex::Definition.from_json(DEFINITION.to_json)
puts "-" * 60
puts "Emails after JSON round-trip: #{restored.send_emails.size}"
