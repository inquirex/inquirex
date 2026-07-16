#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "inquirex"

DEFINITION = Inquirex.define id: "tax-intake-2025", version: "1.0.0" do
  meta title: "Tax Preparation Intake", subtitle: "Let's understand your situation"
  start :filing_status

  ask :filing_status do
    type :enum
    question "What is your filing status?"
    options single: "Single", married_jointly: "Married Filing Jointly"
    widget target: :desktop, type: :radio_group, columns: 2
    widget target: :mobile,  type: :dropdown
    transition to: :dependents
  end

  ask :dependents do
    type :integer
    question "How many dependents?"
    default 0
    transition to: :business_income
  end

  confirm :business_income do
    question "Do you have business income?"
    transition to: :business_count, if_rule: equals(:business_income, true)
    transition to: :done
  end

  ask :business_count do
    type :integer
    question "How many businesses?"
    transition to: :done
  end

  say :done do
    text "Thanks for completing the intake."
  end
end

engine = Inquirex::Engine.new(DEFINITION)

engine.answer("single") # filing_status
engine.answer(2)        # dependents
engine.answer(false)    # business_income
engine.advance          # done (display step)
engine.finished?        # => true

if __FILE__ == $0
  require 'json'
  puts JSON.pretty_generate(DEFINITION.to_h)
end
