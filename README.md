[![Ruby](https://github.com/inquirex/inquirex/actions/workflows/main.yml/badge.svg)](https://github.com/inquirex/inquirex/actions/workflows/main.yml)

# Inquirex

`inquirex` is a pure Ruby, declarative, rules-driven questionnaire engine for building conditional intake forms, qualification wizards, and branching surveys.

It is the core gem in the Inquirex ecosystem and focuses on:

- A conversational DSL (`ask`, `say`, `header`, `btw`, `warning`, `confirm`)
- A serializable AST rule system (`contains`, `equals`, `greater_than`, `less_than`, `not_empty`, `all`, `any`)
- An immutable flow definition graph
- A runtime engine for stateful step traversal
- JSON round-trip serialization for cross-platform clients
- A structured `Answers` wrapper and Mermaid graph export

## Status

- Version: `0.1.0`
- Ruby: `>= 4.0.0` (project currently uses `4.0.2`)
- Test suite: `109 examples, 0 failures`
- Coverage: ~`92.5%` line coverage

## Why Inquirex

Many form builders hard-code branching in controllers, React components, or database callbacks. Inquirex keeps flow logic in one portable graph:

- Define once in Ruby
- Serialize to JSON
- Evaluate transitions consistently using rule AST objects
- Run the same flow in different frontends (web widget, terminal, etc.)

This design is the foundation for the broader ecosystem (`inquirex-ui`, `inquirex-tty`, `inquirex-js`, `inquirex-llm`, `inquirex-rails`).

## Installation

Add to your Gemfile:

```ruby
gem "inquirex"
```

Then install:

```bash
bundle install
```

## Quick Start

```ruby
require "inquirex"

definition = Inquirex.define id: "tax-intake-2025", version: "1.0.0" do
  meta title: "Tax Preparation Intake", subtitle: "Let's understand your situation"
  start :filing_status

  ask :filing_status do
    type :enum
    question "What is your filing status?"
    options single: "Single", married_jointly: "Married Filing Jointly"
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

engine = Inquirex::Engine.new(definition)

engine.answer("single") # filing_status
engine.answer(2)        # dependents
engine.answer(false)    # business_income
engine.advance          # done (display step)

engine.finished? # => true
```

## DSL Overview

### Flow-level methods

- `start :step_id` sets the entry step
- `meta title:, subtitle:, brand:` adds optional frontend metadata

### Step verbs

- Collecting verbs: `ask`, `confirm`
- Display verbs: `say`, `header`, `btw`, `warning`

### Supported input types

- `:string`
- `:text`
- `:integer`
- `:decimal`
- `:currency`
- `:boolean`
- `:enum`
- `:multi_enum`
- `:date`
- `:email`
- `:phone`

### Step options

- `question "..."` for collecting steps
- `text "..."` for display steps
- `options [...]` or `options key: "Label"` for enum-style inputs
- `default value` or `default { |answers| ... }`
- `skip_if rule`
- `transition to: :next_step, if_rule: rule, requires_server: false`
- `compute { |answers| ... }` (accepted by the DSL as a server-side hook; currently omitted from runtime JSON)

## Rule System (AST, JSON-serializable)

Rule helpers available in DSL blocks:

- `contains(:income_types, "Business")`
- `equals(:status, "single")`
- `greater_than(:dependents, 0)`
- `less_than(:age, 18)`
- `not_empty(:email)`
- `all(rule1, rule2, ...)`
- `any(rule1, rule2, ...)`

Example:

```ruby
transition to: :complex_path,
  if_rule: all(
    contains(:income_types, "Business"),
    greater_than(:business_count, 2)
  )
```

## Runtime Engine

`Inquirex::Engine` holds runtime state:

- `current_step_id`
- `current_step`
- `answers` (raw hash)
- `history` (visited step IDs)

Behavior:

- Use `answer(value)` on collecting steps
- Use `advance` on display steps
- Use `finished?` to detect completion
- Use `to_state` / `.from_state` for persistence/resume

### Validation Adapter

Validation is pluggable:

- `Inquirex::Validation::Adapter` (abstract)
- `Inquirex::Validation::NullAdapter` (default, accepts everything)

Pass a custom adapter to the engine:

```ruby
engine = Inquirex::Engine.new(definition, validator: my_validator)
```

## Serialization

Definitions support round-trip serialization:

```ruby
json = definition.to_json
restored = Inquirex::Definition.from_json(json)
```

Serialized structure includes:

- Flow metadata (`id`, `version`, `meta`, `start`)
- Steps and transitions
- Rule AST payloads

Important serialization details:

- Rule objects serialize and deserialize cleanly
- Proc/lambda defaults are stripped from JSON
- `requires_server: true` transition flag is preserved

## Answers Wrapper

`Inquirex::Answers` provides structured answer access:

```ruby
answers = Inquirex::Answers.new(
  filing_status: "single",
  business: { count: 3, type: "llc" }
)

answers.filing_status         # => "single"
answers[:filing_status]       # => "single"
answers.business.count        # => 3
answers.dig("business.count") # => 3
answers.to_flat_h             # => {"filing_status"=>"single", "business.count"=>3, ...}
```

## Mermaid Export

Visualize flow graphs with Mermaid:

```ruby
exporter = Inquirex::Graph::MermaidExporter.new(definition)
puts exporter.export
```

Output is `flowchart TD` syntax with:

- One node per step
- Conditional edge labels from rule `to_s`
- Truncated node content for readability

## Error Types

Common exceptions under `Inquirex::Errors`:

- `DefinitionError`
- `UnknownStepError`
- `SerializationError`
- `AlreadyFinishedError`
- `ValidationError`
- `NonCollectingStepError`

## Development

### Setup

```bash
bin/setup
```

### Run tests

```bash
bundle exec rspec
```

### Lint

```bash
bundle exec rubocop
```

### Useful `just` tasks

```bash
just install
just test
just lint
just lint-fix
just ci
```

## Roadmap Context

This repository is the core runtime (`inquirex`). The full ecosystem roadmap includes:

- `inquirex-ui` for rendering metadata
- `inquirex-tty` for terminal interaction
- `inquirex-js` for embeddable web widget runtime
- `inquirex-llm` for server-side LLM verbs
- `inquirex-rails` for persistence/API integration

## License

MIT. See `LICENSE.txt`.
