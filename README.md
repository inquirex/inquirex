[![Ruby](https://github.com/inquirex/inquirex/actions/workflows/main.yml/badge.svg)](https://github.com/inquirex/inquirex/actions/workflows/main.yml)   ![Coverage](docs/badges/coverage_badge.svg)

# Inquirex

`inquirex` is a pure Ruby, declarative, rules-driven questionnaire engine for building conditional intake forms, qualification wizards, and branching surveys.

It is the core gem in the Inquirex ecosystem and focuses on:

- A conversational DSL (`ask`, `say`, `header`, `btw`, `warning`, `confirm`)
- A serializable AST rule system (`contains`, `equals`, `greater_than`, `less_than`, `not_empty`, `all`, `any`)
- Framework-agnostic widget rendering hints (`widget` DSL verb, `WidgetHint`, `WidgetRegistry`)
- Named **accumulators** for running totals (pricing, complexity scoring, credit scoring, lead qualification)
- An immutable flow definition graph
- A runtime engine for stateful step traversal
- JSON round-trip serialization for cross-platform clients
- A structured `Answers` wrapper and Mermaid graph export

## Status

- Version: `0.2.0`
- Ruby: `>= 4.0.0` (project currently uses `4.0.2`)
- Test suite: `220 examples, 0 failures`
- Coverage: ~`94%` line coverage

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
- `meta title:, subtitle:, brand:, theme:` adds optional frontend metadata (see [Theme](#theme-and-branding))
- `accumulator :name, type:, default:` declares a running total (see [Accumulators](#accumulators))

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
- `widget target: :desktop, type: :radio_group, columns: 2` (rendering hint for frontend adapters)
- `accumulate :name, lookup:|per_selection:|per_unit:|flat:` (contribution to a named running total; see [Accumulators](#accumulators))
- `price ...` (sugar for `accumulate :price, ...`)

## Widget Rendering Hints

Every collecting step can carry framework-agnostic rendering hints via the `widget` DSL verb. Frontend adapters (JS widget, TTY, Rails) use these to pick the right UI control.

```ruby
ask :priority do
  type :enum
  question "How urgent is this?"
  options low: "Low", medium: "Medium", high: "High"
  widget target: :desktop, type: :radio_group, columns: 3
  widget target: :mobile,  type: :dropdown
  widget target: :tty,     type: :select
  transition to: :next_step
end
```

When no explicit `widget` is set, `WidgetRegistry` fills in sensible defaults per data type:

| Data Type | Desktop | Mobile | TTY |
|-----------|---------|--------|-----|
| `:enum` | `radio_group` | `dropdown` | `select` |
| `:multi_enum` | `checkbox_group` | `checkbox_group` | `multi_select` |
| `:boolean` | `toggle` | `yes_no_buttons` | `yes_no` |
| `:string` | `text_input` | `text_input` | `text_input` |
| `:text` | `textarea` | `textarea` | `multiline` |
| `:integer` | `number_input` | `number_input` | `number_input` |
| `:currency` | `currency_input` | `currency_input` | `number_input` |
| `:date` | `date_picker` | `date_picker` | `text_input` |

Display verbs (`say`, `header`, `btw`, `warning`) have no widget hints.

Widget hints are included in JSON serialization under a `"widget"` key, keyed by target:

```json
"widget": {
  "desktop": { "type": "radio_group", "columns": 3 },
  "mobile":  { "type": "dropdown" },
  "tty":     { "type": "select" }
}
```

### Accessing Hints at Runtime

```ruby
step = definition.step(:priority)
step.widget_hint_for(target: :desktop)            # explicit hint or nil
step.effective_widget_hint_for(target: :desktop)   # explicit hint or registry default
```

> **Note:** Widget hints were previously in a separate `inquirex-ui` gem. As of v0.2.0 they are part of core, since every frontend adapter needs them.

## Accumulators

Accumulators are **named running totals** that a flow maintains as the user answers questions. The canonical use case is **pricing** — totalling the cost of a tax return, a SaaS quote, or an insurance premium — but the same primitive generalizes to **complexity scoring**, **credit scoring**, **lead qualification scores**, **risk scores**, or any other numeric tally.

Like rules, accumulator declarations are **pure data**. They serialize to JSON and evaluate identically on the Ruby server and in the JS widget — no lambdas, no server round-trips.

### Declaring accumulators

Each flow declares one or more accumulators with a name, a type, and a starting value:

```ruby
Inquirex.define id: "tax-pricing-2025" do
  accumulator :price,      type: :currency, default: 0
  accumulator :complexity, type: :integer,  default: 0
  # ...
end
```

### Contributing to an accumulator from a step

Use the `accumulate` verb inside any `ask`/`confirm` step. Exactly one **shape** key must be provided:

| Shape | Fits | Semantics |
|-------|------|-----------|
| `lookup: { ... }` | `:enum` | Adds the amount mapped to the chosen option value |
| `per_selection: { ... }` | `:multi_enum` | Sums the amounts for every selected option |
| `per_unit: N` | `:integer`, `:decimal` | Multiplies the numeric answer by `N` |
| `flat: N` | any type | Adds `N` when the step has a truthy, non-empty answer |

```ruby
ask :filing_status do
  type :enum
  question "Filing status?"
  options single: "Single", mfj: "Married Filing Jointly", hoh: "Head of Household"
  accumulate :price,      lookup: { single: 200, mfj: 400, hoh: 300 }
  accumulate :complexity, lookup: { mfj: 1 }
  transition to: :dependents
end

ask :dependents do
  type :integer
  question "How many dependents?"
  default 0
  accumulate :price, per_unit: 25          # $25 per dependent
  transition to: :schedules
end

ask :schedules do
  type :multi_enum
  question "Which schedules apply?"
  options c: "Schedule C (Business)",
    e: "Schedule E (Rental)",
    d: "Schedule D (Capital Gains)"
  accumulate :price,      per_selection: { c: 150, e: 75, d: 50 }
  accumulate :complexity, per_selection: { c: 2, e: 1, d: 1 }
  transition to: :done
end
```

A single step can contribute to any number of accumulators.

### The `price` sugar

Since `:price` is the most common use case (lead qualification, tax prep, SaaS quotes), there's a one-liner:

```ruby
price single: 200, mfj: 400, hoh: 300   # => accumulate :price, lookup: { ... }
price per_unit: 25                       # => accumulate :price, per_unit: 25
price per_selection: { c: 150, e: 75 }   # => accumulate :price, per_selection: { ... }
```

If you pass a plain option-value → amount hash (no shape key), `price` treats it as a `lookup`.

### Reading totals at runtime

The engine maintains running totals as each answer comes in:

```ruby
engine = Inquirex::Engine.new(definition)
engine.answer("mfj")     # filing_status: +$400, +1 complexity
engine.answer(3)         # dependents:    +$75
engine.answer(%w[c e])   # schedules:     +$225, +3 complexity

engine.total(:price)      # => 700.0
engine.total(:complexity) # => 4
engine.totals             # => { price: 700.0, complexity: 4 }
```

`#to_state` includes `totals:` so persisted sessions resume with the correct running total.

### JSON wire format

Accumulators serialize predictably, keeping the contract with `inquirex-js` explicit:

```json
{
  "accumulators": {
    "price":      { "type": "currency", "default": 0 },
    "complexity": { "type": "integer",  "default": 0 }
  },
  "steps": {
    "filing_status": {
      "verb": "ask",
      "type": "enum",
      "accumulate": {
        "price":      { "lookup": { "single": 200, "mfj": 400, "hoh": 300 } },
        "complexity": { "lookup": { "mfj": 1 } }
      }
    },
    "dependents": {
      "verb": "ask",
      "type": "integer",
      "accumulate": { "price": { "per_unit": 25 } }
    },
    "schedules": {
      "verb": "ask",
      "type": "multi_enum",
      "accumulate": {
        "price":      { "per_selection": { "c": 150, "e": 75, "d": 50 } },
        "complexity": { "per_selection": { "c": 2, "e": 1, "d": 1 } }
      }
    }
  }
}
```

The `inquirex-js` widget reads this verbatim and reproduces the same totals client-side.

## Theme and Branding

The flow's `meta` hash carries optional branding and theme overrides for the JS widget. Identity (name, logo) goes in `brand:`; colors, fonts, and radii go in `theme:`.

```ruby
meta title: "Tax Preparation Intake",
  subtitle: "Let's understand your situation",
  brand: { name: "Agentica", logo: "https://cdn.example.com/logo.png" },
  theme: {
    brand:       "#2563eb",
    on_brand:    "#ffffff",
    background:  "#0b1020",
    surface:     "#111827",
    text:        "#f9fafb",
    text_muted:  "#94a3b8",
    border:      "#1f2937",
    radius:      "18px",
    font:        "Inter, system-ui, sans-serif",
    header_font: "Inter, system-ui, sans-serif"
  }
```

Snake-case keys (`on_brand`, `text_muted`, `header_font`) are idiomatic Ruby; they're automatically translated to the camelCase names (`onBrand`, `textMuted`, `headerFont`) the JS widget expects on the wire. Each theme key maps 1:1 to a CSS custom property on the widget's shadow root.

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
- `totals` (running totals per accumulator — see [Accumulators](#accumulators))

Behavior:

- Use `answer(value)` on collecting steps
- Use `advance` on display steps
- Use `finished?` to detect completion
- Use `total(:price)` / `totals` to read running totals
- Use `to_state` / `.from_state` for persistence/resume (totals included)
- Use `prefill!(hash)` to merge externally-supplied answers into the state,
  e.g. fields extracted by an LLM from a free-text answer (see
  [inquirex-llm](#extension-gems)). Existing answers are preserved; `nil`
  and empty values are ignored so they don't spuriously satisfy
  `not_empty` rules. The engine auto-advances past any newly-skippable step.

```ruby
engine = Inquirex::Engine.new(definition)
engine.answer("I'm MFJ with two kids in California.") # free-text :describe

# Step is now :extracted (a clarify node); adapter returns a Hash.
result = adapter.call(engine.current_step, engine.answers)
engine.answer(result)           # store under the clarify step's id
engine.prefill!(result)         # splat into top-level answers
# Downstream :filing_status, :dependents, :state are now auto-skipped by
# `skip_if not_empty(:filing_status)` etc.
```

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
- Branding and theme (`meta.brand`, `meta.theme`)
- Accumulator declarations (`accumulators`) and per-step contributions (`accumulate`)
- Steps and transitions
- Rule AST payloads
- Widget hints

Important serialization details:

- Rule objects and accumulator shapes serialize and deserialize cleanly
- Proc/lambda defaults are stripped from JSON
- `requires_server: true` transition flag is preserved
- Snake-case theme keys are converted to camelCase on serialization to match the JS widget contract

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

## Extension Gems

The core gem is designed to be extended by optional gems that inject new DSL verbs at `require` time:

```ruby
require "inquirex"       # core DSL, rules, engine, widget hints
require "inquirex-llm"   # adds: clarify, describe, summarize, detour

Inquirex.define do       # one entry point, all verbs available
  # ...
end
```

### Ecosystem

- **`inquirex-llm`** -- LLM-powered verbs (`clarify`, `describe`, `summarize`, `detour`) for server-side AI processing
- **`inquirex-tty`** -- terminal adapter using TTY Toolkit
- **`inquirex-js`** -- embeddable browser widget (chat-style)
- **`inquirex-rails`** -- Rails Engine for persistence, API, and asset serving

> **Note:** `inquirex-ui` has been merged into core as of v0.2.0. Widget hints (`widget` DSL verb, `WidgetHint`, `WidgetRegistry`) are now built in.

## License

MIT. See `LICENSE.txt`.
