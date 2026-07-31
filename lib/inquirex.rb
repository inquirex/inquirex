# frozen_string_literal: true

require_relative "inquirex/version"
require_relative "inquirex/errors"

# Rules subsystem
require_relative "inquirex/rules/base"
require_relative "inquirex/rules/contains"
require_relative "inquirex/rules/equals"
require_relative "inquirex/rules/greater_than"
require_relative "inquirex/rules/less_than"
require_relative "inquirex/rules/not_empty"
require_relative "inquirex/rules/all"
require_relative "inquirex/rules/any"

# Widget hints
require_relative "inquirex/widget_hint"
require_relative "inquirex/widget_registry"

# Core graph objects
require_relative "inquirex/transition"
require_relative "inquirex/evaluator"
require_relative "inquirex/accumulator"
require_relative "inquirex/node"
require_relative "inquirex/email"
require_relative "inquirex/template_refs"
require_relative "inquirex/definition"
require_relative "inquirex/answers"
require_relative "inquirex/completion_metadata"

# Validation
require_relative "inquirex/validation/adapter"
require_relative "inquirex/validation/null_adapter"

# Post-completion actions (deprecated; see Inquirex::Actions)
require_relative "inquirex/actions"
require_relative "inquirex/actions/template"
require_relative "inquirex/actions/outbox"
require_relative "inquirex/actions/base"
require_relative "inquirex/actions/send_email"
require_relative "inquirex/actions/action"
require_relative "inquirex/actions/runner"

# DSL
require_relative "inquirex/dsl"
require_relative "inquirex/dsl/rule_helpers"
require_relative "inquirex/dsl/step_builder"
require_relative "inquirex/dsl/email_builder"
require_relative "inquirex/dsl/flow_builder"
require_relative "inquirex/dsl/action_builder"

# Safe evaluation of DSL source (must follow the DSL, whose vocabulary it binds to)
require_relative "inquirex/safe_source"

# Engine
require_relative "inquirex/engine/state_serializer"
require_relative "inquirex/engine"

# Graph utilities
require_relative "inquirex/graph/mermaid_exporter"

# Declarative, rules-driven questionnaire engine for building conditional intake forms,
# qualification wizards, and branching surveys.
#
# @example Define a flow
#   definition = Inquirex.define id: "tax-intake-2025" do
#     meta title: "Tax Preparation Intake", subtitle: "Let's understand your situation"
#     start :filing_status
#
#     ask :filing_status do
#       type :enum
#       question "What is your filing status?"
#       options single: "Single", married_jointly: "Married Filing Jointly"
#       transition to: :dependents
#     end
#
#     ask :dependents do
#       type :integer
#       question "How many dependents?"
#       default 0
#       transition to: :done
#     end
#
#     say :done do
#       text "Thank you!"
#     end
#   end
#
#   engine = Inquirex::Engine.new(definition)
#   engine.answer("single")
#   engine.answer(2)
#   engine.advance              # past the :done say step
#   engine.finished?            # => true
#
# @example JSON round-trip
#   json = definition.to_json
#   restored = Inquirex::Definition.from_json(json)
#
module Inquirex
  # Builds an immutable Definition from the declarative DSL block.
  #
  # @param id [String, nil] optional flow identifier
  # @param version [String] semver (default: "1.0.0")
  # @yield context of DSL::FlowBuilder
  # @return [Definition]
  def self.define(id: nil, version: "1.0.0", &)
    builder = DSL::FlowBuilder.new(id:, version:)
    builder.instance_eval(&)
    builder.build
  end

  # Evaluates a string of DSL code and returns the resulting definition.
  # Intended for loading flow definitions from files or stored text.
  #
  # This is an `eval`. Since 0.7.0 the source is therefore validated against the
  # flow-DSL allowlist ({SafeSource}) *before* anything is evaluated, so text
  # from a database column, an upload, an LLM or a visual builder cannot execute
  # arbitrary Ruby in the loading process.
  #
  # Pass `unsafe: true` only for source you control as code — a `.rb` file in
  # your own repository, a heredoc in your own test, the fixture inquirex-tty
  # was pointed at. It skips validation entirely, which is the only way to use
  # `compute`, a block-form `default`, `fallback` or an action's `run`, all of
  # which are arbitrary Ruby by definition and cannot be validated. If the text
  # reached you over a network or out of a database, it is not trusted, whatever
  # the flow needs.
  #
  # @example Customer-authored source (validated)
  #   Inquirex.load_dsl(qualifier.flow_dsl)
  #
  # @example Your own file, with lambdas in it
  #   Inquirex.load_dsl(File.read("flows/tax_intake.rb"), unsafe: true)
  #
  # @param text [String] Ruby source containing Inquirex.define { ... }
  # @param unsafe [Boolean] skip validation; only for source you wrote yourself
  # @param max_bytes [Integer] override SafeSource's source-size ceiling
  # @param max_depth [Integer] override SafeSource's nesting-depth ceiling
  # @return [Definition]
  # @raise [Errors::UnsafeSourceError] when the source is outside the allowlist
  # @raise [Errors::DefinitionError] on syntax or evaluation errors
  def self.load_dsl(text,
    unsafe: false,
    max_bytes: SafeSource.max_source_bytes,
    max_depth: SafeSource.max_depth)
    SafeSource.validate!(text, max_bytes:, max_depth:) unless unsafe

    begin
      # rubocop:disable Security/Eval
      eval(text, TOPLEVEL_BINDING.dup, "(dsl)", 1)
      # rubocop:enable Security/Eval
    rescue SyntaxError => e
      raise Errors::DefinitionError, "DSL syntax error: #{e.message}"
    rescue StandardError => e
      raise Errors::DefinitionError, "DSL evaluation error: #{e.message}"
    end
  end
end
