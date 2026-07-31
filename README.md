[![Gem Version](https://badge.fury.io/rb/inquirex.svg)](https://badge.fury.io/rb/inquirex) [![Ruby](https://github.com/inquirex/inquirex/actions/workflows/main.yml/badge.svg)](https://github.com/inquirex/inquirex/actions/workflows/main.yml) ![Coverage](docs/badges/coverage_badge.svg)

# Inquirex

`inquirex` family of libraries (part Ruby, part JavaScript), is a declarative, rules-driven questionnaire engine for building conditional intake forms, qualification wizards, and branching surveys, which can be AI-enabled, and rendered on your site inside a "copilot" widget window or in a TUI (Terminal UI) all the same.

> [!IMPORTANT]
>
> Today the ecosystem contains:
>
> - [`inquirex`](https://github.com/inquirex/inquirex): the base gem that defines the graph via DSL and provides most of the backend features
> - [`inquirex-llm`](https://github.com/inquirex/inquirex-llm): a tiny gem that extends the DSL by the word `extract` which, given a previous question answered in the form of free text, can use the model of your choice to return structured breakdown of text into answers to questions that might follow, thus shortening the form considerably.
> - [`inquirex-tty`](https://github.com/inquirex/inquirex-tty): is the gem that renders the forms on the TUI (Terminal UI). This is also the gem that provides the CLI `inqurex` for performing various tasks such as validating DSL files, converting them from Ruby to JSON and back, and more. It is also the gem where a folder of DSL `examples` can be used to get a feel for how this works.
> - [`inquirex-js`](https://github.com/inquirex/inquirex-js) (`npmjs` module [`@kigster/inquirex-js`](https://www.npmjs.com/package/@kigster/inquirex-js)) is the NPM package that connects web UI with the form definition in JSON format. If LLM is not needed, the entire flow becomes deterministic and collects answers as the user answers your questions, and then POSTS them to the URL of your choice.
>
> For a presentation about these gems and what they do please watch the [RubySF presentation](https://www.youtube.com/watch?v=iaoKW7Ap3_M&t=1s) and you can also [view the slides form the presentation](https://reinvent.one/images/talks/pdfs/2026.inquirex.pdf).
>
> Finally, the SaaS application [qualified.at](https://qualified.at) allows busy professionals such as consultants, doctors, tax-preparers, who are short on time, or can't be bothered to figure out the technical side of integrating these libraries, to leverage the entire ecosystem by creating their own custom lead intake forms on the SaaS application, dropping the auto-generated widget on their (potentially static website), and showing the copilot to their customers, customizing from nothing at all, to what triggers copilot's appearance, it's look and feel, and so on. The site automatically supports the LLM keyword `extract` as part of the DSL, and also collects the answers from your leads in your account: the data that you own, and can export at any time into a CSV download, a Google Spreadsheet, etc.

## Why Inquirex?

There are plenty of form builders, state machines, workflow libraries, etc. And yet, none of them combine the convenience of a DSL with logical separation between the form substance, and the rendering UI quite like this.

There are plenty of form building gems, hard-coded branching controllers, React components, or database callbacks.

***Inquirex is quite different.***

It provides a rich DSL for creating dynamic user intake forms, with complexity ranging from a simple straight-line forms to multi-branch, conditional forms with dozens of potential branches, *UI widget hints* for various rendering platforms, with *accumulators* that allow computing sums or products based on user's answers (which allow you to compute — for user or for yourself — that the service you are requesting will cost between $X & $Y).

> [!NOTE]
>
> For technically inclined, Inquirex turns user forms into a directed graph, where nodes are either questions or statements (or UI transitions), while edges are AST-based logical conditions that can be stacked and joined in arbitrarily complex ways, allowing you to move from one question to any other based on the previous answer. See the details below.

***Don't want to deal with figuring it out? Head to [Qualified.At](https://qualified.at) and walk through the demo onboarding form, that exists specifically to show you how quickly you can have the same conceptually on your site, tailored to YOUR users.***

## Summary

This one is the core gem in the Inquirex ecosystem that focuses on:

- A conversational DSL (`ask`, `say`, `header`, `btw`, `warning`, `confirm`)

- A serializable AST rule system (`contains`, `equals`, `greater_than`, `less_than`, `not_empty`, `all`, `any`)

- Framework-agnostic widget rendering hints (`widget` DSL verb, `WidgetHint`, `WidgetRegistry`)

- Named ***accumulators*** for running totals (pricing, complexity scoring, credit scoring, lead qualification)

- Liquid `{{ }}` placeholders in every user-facing string, so a question can greet the visitor by the name they gave two steps ago (see [Liquid Placeholders](#liquid-placeholders-in-user-facing-text))

- A top-level `send_email` declaration, and an advisory `Engine#on_complete_actions` list the host chooses what to do with (see [Declaring Emails](#declaring-emails))

- An immutable flow definition graph

- A runtime engine for stateful step traversal

- JSON round-trip serialization for cross-platform clients

- A default-deny AST allowlist (`SafeSource`) so DSL text written by someone you do not trust can be loaded without handing them an `eval` (see [Loading DSL Source](#loading-dsl-source))

- A structured `Answers` wrapper and Mermaid graph export (provided by `inquirex-tty` gem's CLI)

- In short:

  - Define once in Ruby
  - Serialize to JSON if you need to show the questions on the web UI
  - Evaluate transitions consistently using rule AST objects
  - Run the same flow identically in concept in different frontends (web widget, TUI, etc.)

So, if you ever wanted to ask users who arrive at your site a few simple questions (PII questions are strongly discouraged due to the fact that the gem is typically used by non-logged in users on your end — except, perhaps, name and email), and depending on their answers you might want to dig a bit deeper, so that once you get on the phone with them you'll already have a general picture, these gems are for you (or head to [qualified.at](https://qualified.at) and set up your free account to see how this works in practice.

## Examples

> [!NOTE]
>
> There are a couple of examples shown in this `README` file, and also in the [`./examples`](./examples) folder. You can read about running them in a [`README.md`](./examples/README.md) inside that folder.

## Installation

Add to your Gemfile:

```ruby
gem "inquirex"
#  if you are building a TUI or need the CLI version of this gem
gem "inquirex-tty" 
#  if you want to add the keyword `extract` to the DSL vocabilary
gem "inquire-llm"  
```

Then install:

```bash
bundle install
```

And then, define your form as a Ruby DSL file (see [examples](https://github.com/inquirex/inquirex-tty/tree/main/examples) on Github), and consume it by either the `inquirex-tty` gem on the command line, or on the web via the [@kigster/inqiurex-js](https://www.npmjs.com/package/@kigster/inquirex-js) npmjs package.

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
- `send_email do ... end` declares an email for the host to send on completion (see [Declaring Emails](#declaring-emails))
- `action :id do ... end` — **deprecated**, see [Post-Completion Actions](#post-completion-actions-deprecated)

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
- `default value` or `default { |answers| ... }` (the block form needs `unsafe: true`, see [Loading DSL Source](#loading-dsl-source))
- `required false` (marks a question optional — renderers show a Skip control; see [Optional Questions and Skipping](#optional-questions-and-skipping))
- `skip_if rule`
- `transition to: :next_step, if_rule: rule, requires_server: false`
- `compute { |answers| ... }` (server-side hook; omitted from runtime JSON, and needs `unsafe: true`)
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

| Data Type     | Desktop          | Mobile           | TTY            |
| ------------- | ---------------- | ---------------- | -------------- |
| `:enum`       | `radio_group`    | `dropdown`       | `select`       |
| `:multi_enum` | `checkbox_group` | `checkbox_group` | `multi_select` |
| `:boolean`    | `toggle`         | `yes_no_buttons` | `yes_no`       |
| `:string`     | `text_input`     | `text_input`     | `text_input`   |
| `:text`       | `textarea`       | `textarea`       | `multiline`    |
| `:integer`    | `number_input`   | `number_input`   | `number_input` |
| `:currency`   | `currency_input` | `currency_input` | `number_input` |
| `:date`       | `date_picker`    | `date_picker`    | `text_input`   |

Display verbs (`say`, `header`, `btw`, `warning`) have no widget hints.

Widget hints are included in JSON serialization under a `"widget"` key, keyed by target:

```json
{
  "widget": {
    "desktop": {
      "type": "radio_group",
      "columns": 3
    },
    "mobile": {
      "type": "dropdown"
    },
    "tty": {
      "type": "select"
    }
  }
}
```

### Accessing Hints at Runtime

```ruby
step = definition.step(:priority)
step.widget_hint_for(target: :desktop)             # explicit hint or nil
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

| Shape                    | Fits                   | Semantics                                             |
| ------------------------ | ---------------------- | ----------------------------------------------------- |
| `lookup: { ... }`        | `:enum`                | Adds the amount mapped to the chosen option value     |
| `per_selection: { ... }` | `:multi_enum`          | Sums the amounts for every selected option            |
| `per_unit: N`            | `:integer`, `:decimal` | Multiplies the numeric answer by `N`                  |
| `flat: N`                | any type               | Adds `N` when the step has a truthy, non-empty answer |

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

Accumulators serialize predictably, keeping the contract with `inquirex-js` explicit.

> [!NOTE]
>
> You can convert between Ruby DSL and JSON using the [`inquirex-tty`](https://github.com/inquirex/inquirex-tty) gem.

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
- Use `skip` on optional (`required false`) collecting steps the user declines (see [Optional Questions and Skipping](#optional-questions-and-skipping))
- Use `finished?` to detect completion
- Use `total(:price)` / `totals` to read running totals
- Use `to_state` / `.from_state` for persistence/resume (totals included)
- Use `prefill!(hash)` to merge externally-supplied answers into the state, e.g. fields extracted by an LLM from a free-text answer (see [inquirex-llm](#extension-gems)). Existing answers are preserved; `nil` and empty values are ignored so they don't spuriously satisfy `not_empty` rules. The engine auto-advances past any newly-skippable step.
- Use `render_context` to get the plain, JSON-serializable Hash you bind when rendering a step's Liquid placeholders (see [Liquid Placeholders](#liquid-placeholders-in-user-facing-text))
- Use `on_complete_actions` once finished to get the advisory list of things the flow asks the host to do (see [Declaring Emails](#declaring-emails))

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

## Optional Questions and Skipping

Every collecting step is **required by default** — the flow will not advance without an answer. Declare `required false` to make a question optional: renderers (the JS widget, the TTY adapter, the qualified.at wizard) show a small **Skip** control next to the input, and a user who declines the question moves on via `Engine#skip`.

```ruby
ask :dependents do
  type :integer
  question "How many dependents?"
  required false        # renders a Skip control
  default 0             # what a skip records into the answers
  transition to: :adult_path, if_rule: greater_than(:dependents, 0)
  transition to: :done
end
```

When the user skips:

- **With a `default`** — the default is recorded into `answers[:dependents]` and contributes to [accumulators](#accumulators) exactly as if the user had submitted it. Transition rules evaluate against the default, so branching stays deterministic.
- **Without a `default`** — no answers entry is written at all (not even `nil`). Rules read a missing key as `nil`, so branching behaves as if the question were unanswered.
- Either way the step id lands in `engine.skipped`, which is how a defaulted-by-skip value is **distinguished from an answer the user actually provided**:

```ruby
engine.skip                     # user pressed Skip on :dependents
engine.answers[:dependents]     # => 0 (the default)
engine.skipped                  # => [:dependents]
engine.skipped?(:dependents)    # => true
```

Guard rails:

- `skip` on a **required** step raises `Errors::RequiredStepError`
- `skip` on a **display** step raises `Errors::NonCollectingStepError` (use `advance`)
- `skip` after the flow finished raises `Errors::AlreadyFinishedError`

The `skipped` list survives `to_state` / `.from_state` round-trips (string keys from JSON are normalized back to symbols), and `engine.answers_with_metadata` merges it into the answers under `:skipped` — so a host rendering a `send_email` template, or an API consumer, can see which values were defaults-by-skip.

On the wire, step JSON carries `"required": false` (omitted when true, like other defaults):

```json
{
  "dependents": {
    "verb": "ask",
    "type": "integer",
    "question": "How many dependents?",
    "default": 0,
    "required": false,
    "transitions": [{ "to": "done" }]
  }
}
```

> [!NOTE]
>
> **`skip_if` is not the same thing.** A `skip_if` rule is *flow logic*: the definition elides the step from the path automatically, no default kicks in, and the step is **not** added to `engine.skipped` — it was never presented, so the user cannot have declined it. `Engine#skip` is a *user action* on a question that was presented. See [`docs/design/required-and-skip.md`](docs/design/required-and-skip.md) for the full design.

## Completion Metadata

When a flow finishes, the engine guarantees a `CompletionMetadata` — an OpenStruct describing how the answers were collected. Only `engine` and `engine_version` are required members; rendering front-ends attach richer environment details from an `after_completion` hook:

```ruby
engine.after_completion do |eng|
  eng.completion_metadata = Inquirex::CompletionMetadata.new(
    engine:         "inquirex-tty",
    engine_version: Inquirex::TTY::VERSION,
    uname:          OpenStruct.new(Etc.uname),
    user:           Etc.getlogin,
    terminal:       ENV["LC_TERMINAL"] || ENV["TERM_PROGRAM"] || "Unknown"
  )
end
```

If no hook supplies one, the engine stamps the minimal core version (`engine: "inquirex"`, `engine_version: Inquirex::VERSION`). The metadata persists through `Engine#to_state` / `Engine.from_state`, and `engine.answers_with_metadata` merges it into the answers hash under `:completion_metadata` — which also makes it available when a host renders templates — `{{ answers.completion_metadata.engine }}` resolves if you bind `answers_with_metadata` rather than `answers`.

## Liquid Placeholders in User-Facing Text

Every user-facing string in the DSL — a step's `question`, a display step's `text`, and every `send_email` field — may carry [Liquid](https://shopify.github.io/liquid/) `{{ }}` placeholders referring to earlier answers and to accumulator totals:

```ruby
ask :email do
  type :email
  question "Thanks {{ answers.name }}, where can we reach you?"
  transition to: :quote
end

say :quote do
  text "{{ answers.name }}, your estimate starts at ${{ accumulators.price | round: 2 }}."
end
```

**`{{ }}` is data. `#{}` is Ruby, and is forbidden.** The two look similar and are not variations on a theme. Ruby interpolation in a stored flow definition is arbitrary code execution, which is why [`SafeSource`](#loading-dsl-source) rejects it outright; Liquid reaches the same result as pure data. Adding `{{ }}` therefore *relieves* pressure on the security boundary rather than widening it — it is the supported way to do the thing authors otherwise reach for `#{}` to achieve. Nothing in the allowlist had to change to permit it: to the parser, `{{ answers.name }}` is ordinary text inside a string literal.

Two rules follow from the zero-dependency policy:

- **The gem stores, the host renders.** `Node#question`, `Node#text` and the `Email` fields all return the raw source. This gem has no Liquid dependency and never renders anything.
- **Render at display time, not at load time.** Answers accumulate as the wizard progresses, so a question shown at step 4 may reference an answer collected at step 2. Take the context fresh each time you render:

```ruby
Liquid::Template.parse(engine.current_step.question).render(engine.render_context)
```

`Engine#render_context` is a plain, JSON-serializable Hash — Symbol keys and values become Strings, nesting is preserved:

```ruby
engine.render_context
# => { "answers"      => { "name" => "Ada", "status" => "business" },
#      "accumulators" => { "price" => 400 } }
```

The drop names (`answers`, `accumulators`) are a convention this gem documents rather than enforces — it never renders, so it attaches no meaning to them.

### Catching typos before a lead sees them

`Definition#template_warnings` scans every user-facing string for references that resolve to nothing:

```ruby
definition.template_warnings
# => ["step :email question references {{ answers.phone }}, which no step collects",
#     "send_email #1 to references {{ accumulators.total }}, which is not a declared accumulator"]
```

It is deliberately **advisory** — Liquid renders an unknown reference as an empty string, and definitions with warnings still load and run. Surface these in an editor or a CI check; do not gate loading on them. It is also deliberately partial: full Liquid syntax cannot be parsed without Liquid, so `Inquirex::TemplateRefs` recognizes `{{ answers.X }}` and `{{ accumulators.Y }}` and passes over anything else in silence rather than rejecting it on a guess.

## Declaring Emails

A flow declares the email it wants sent with a top-level `send_email` block. Each word is a setter taking one template string, matching the rest of the DSL's idiom:

```ruby
Inquirex.define do
  start :name
  # ... ask steps ...

  send_email do
    to      "{{ answers.email }}"
    from    "Qualified.At"
    subject "Thank you for filling the form"
    body_markdown <<~'TEXT'
      Dear {{ answers.name }},

      Thank you for filling out the form. Your total is
      ${{ accumulators.price | round: 2 }} minimum.
    TEXT
  end
end
```

Declare as many as the flow needs; they serialize in declaration order under the `"emails"` key.

Key semantics:

- **The gem declares, the host renders.** `Inquirex::Email` holds four opaque template strings. It never renders them, never converts Markdown, never builds a message and never delivers anything. Rendering would mean depending on a template engine, a Markdown converter and a mailer, and the core gem has no required runtime dependencies. This is the same division of labour as lambdas: the definition describes intent, the server-side host owns execution.
- **`body_markdown` is the single body source.** There is no `body_html` and no `body_text`. Markdown is designed to read as plain text, so the host renders `text/plain` from it as-is and `text/html` from Markdown → HTML. One source, two MIME parts, nothing to keep in sync.
- **No function calls in the DSL.** Format is a property of the body (`body_markdown`), not something you call on it. There is no `markdown_to_html(...)` helper and there will not be one.
- **Write bodies with a single-quoted heredoc** (`<<~'TEXT'`). A plain `<<~TEXT` interpolates `#{}` in Ruby before the template ever reaches Liquid, which is exactly the hole `SafeSource` closes for stored DSL.
- **Liquid syntax is checked at definition time when Liquid happens to be loaded.** `Inquirex::Email.liquid_template_class` looks the class up at call time; if the host has Liquid (every Rails app that renders these does), each field is parsed in strict mode so an authoring typo raises where the author can see it. If it does not, the strings are stored verbatim and nothing breaks.

### `Engine#on_complete_actions`

Once the flow finishes, the engine hands back what the flow *asks* the host to do:

```ruby
engine.on_complete_actions
# => [{ "type"          => "send_email",
#       "to"            => "{{ answers.email }}",
#       "from"          => "Qualified.At",
#       "subject"       => "Thank you for filling the form",
#       "body_markdown" => "Dear {{ answers.name }},\n...",
#       "context"       => { "answers"      => { "name" => "Ada", "email" => "ada@x.io" },
#                            "accumulators" => { "price" => 400 } } }]
```

```ruby
engine.on_complete_actions.each do |action|
  next unless action["type"] == "send_email"

  OutboundMailJob.perform_later(action)   # renders Liquid + Markdown, then delivers
end
```

- **The list is advisory.** The gem sends nothing, builds no `Mail::Message` and tracks no delivery. A host may process all of it, some of it or none of it. That framing is what keeps future action types (a webhook, a CRM push) additive: loop over the array and handle the `"type"` values you recognize.
- **Templates are raw, and the context travels with them.** The gem cannot render — no Liquid — so each entry pairs its templates with a snapshot equal to `Engine#render_context`. That makes an entry self-contained: a background job can pick it up minutes later, with no engine and no session, and still have everything it needs. The context repeats per action, which is the right trade for a payload measured in kilobytes.
- **Everything in it is plain JSON.** `JSON.parse(JSON.generate(actions)) == actions`, so it can go straight into a queue.
- Empty until `engine.finished?`.

## Post-Completion Actions (deprecated)

> [!WARNING]
>
> The `action` verb is **deprecated as of 0.7.0** and will be removed in 0.8.0. It is retained only so flow definitions hosts already store keep loading. New flows use the top-level [`send_email`](#declaring-emails) declaration, which the gem serializes and the host renders — no `mail` gem, no template engine, nothing to execute.

`action` declarations run server-side after a flow finishes, building `Mail::Message` objects into `answers.outbox`; nothing is delivered.

```ruby
action :client_receipt, if: not_empty(:email) do
  send_email to:      "{{email}}",
             from:    "forms@agentica.group",
             subject: "Thanks {{name}} — we received your intake",
             text:    "Hi {{name}}\n\n{{answers_summary}}",
             html:    "<p>Hi {{name}}</p>{{answers_summary}}"
end
```

```ruby
answers = Inquirex::Actions.run(definition, engine.answers)
answers.outbox.messages   # => [Mail::Message, ...]
answers.outbox.results    # => per-action :ok / :skipped / :failed trail
```

Note the different templating: the effect renders `{{field}}` against `Answers#to_flat_h` itself (`Inquirex::Actions::Template`), which is *not* Liquid. That divergence is one of the reasons the verb is going away.

**Removed outright in 0.7.0** — not merely refused in safe mode, so `unsafe: true` does not bring them back:

- **`run { |answers, outbox| ... }`** — arbitrary Ruby in a document that may have come from a database column.
- **`webhook url:`** and the top-level **`allowed_domains`** declaration — the destination host was authorized by the allowlist declared in the *same untrusted document*, and plain `http` to localhost was permitted, making it an egress and SSRF primitive granted to whoever authored the text. A host that wants customer-configured webhooks should own that configuration.
- **`send_email text:`/`html:` given as `{ file: "path" }`** — the gem `File.read` it at definition time, i.e. arbitrary file disclosure with an attacker-chosen recipient.

Everything an `action` can still express is serializable, so nothing is stripped from JSON any more.

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
- `send_email` declarations (`emails`), in declaration order, as raw template strings
- Deprecated post-completion actions (`actions`) with their rules and effects; nothing is stripped, since every effect is now serializable

Important serialization details:

- Rule objects and accumulator shapes serialize and deserialize cleanly
- Proc/lambda defaults are stripped from JSON
- `requires_server: true` transition flag is preserved
- `required: false` step flag is preserved (omitted when true, the default)
- Snake-case theme keys are converted to camelCase on serialization to match the JS widget contract

## Loading DSL Source

`Inquirex.load_dsl(text)` turns DSL *source* into a `Definition`. It is an `eval`, so since 0.7.0 it validates the text against the flow-DSL allowlist before evaluating anything:

```ruby
# Text you did not write — a database column, an upload, an LLM, a builder's
# "sync" button. Validated first; a payload raises before it can run.
definition = Inquirex.load_dsl(qualifier.flow_dsl)

# Source you control as code, e.g. a file in your own repository. Skips
# validation, which is the only way to use compute, a block-form default or
# fallback — all of which are arbitrary Ruby by definition.
definition = Inquirex.load_dsl(File.read("flows/tax_intake.rb"), unsafe: true)
```

`Inquirex::SafeSource` answers "would `load_dsl` accept this?" without evaluating, which is what you want when auditing what is already stored:

```ruby
Inquirex::SafeSource.safe?(source)     # => true / false
Inquirex::SafeSource.validate(source)  # => ["line 4: `compute` is not available in safe mode: ..."]
Inquirex::SafeSource.validate!(source) # raises Inquirex::Errors::UnsafeSourceError
```

How it decides: the source is parsed with Prism and walked by recursive descent against an *expected shape*. At each position only the node types the real DSL produces there are accepted — so a construct nobody anticipated is rejected by construction, unlike a blocklist of forbidden method names. Concretely, the document must be a single `Inquirex.define` block containing only the real vocabulary (`Inquirex::SafeSource::Vocabulary`, whose flow verbs come from `Node::VERBS`, step types from `Node::TYPES` and rules from `DSL::RuleHelpers`) with literal arguments. Constants, variables, interpolation, method calls, `require`, `begin/rescue`, backticks and Ruby blocks outside the DSL's own nested scopes are all violations.

Deliberately not available in safe mode:

- `compute`, a block-form `default` and `fallback` — a Ruby block cannot be validated; a `compute` block is indistinguishable from a payload

Note what is *not* on that list any more. The `webhook` effect, the `allowed_domains` declaration, an action's `run` block and the `{ file: "path" }` body form were **removed from the gem** in 0.7.0 rather than merely refused here (see [Post-Completion Actions](#post-completion-actions-deprecated)). Deletion is the stronger guarantee: there is no `unsafe: true` that brings them back.

Liquid `{{ }}` placeholders need no allowlist entry at all — to the parser they are ordinary text inside a string literal. That is the argument for using them: they give an author what `#{}` would, as data, with nothing to execute.

Two ceilings apply, both measured against real flows (the largest is under 6 KB, the deepest legitimate construct 9 levels) and both overridable:

```ruby
Inquirex::SafeSource.max_source_bytes = 256 * 1024  # default 64 KiB
Inquirex::SafeSource.max_depth = 32                 # default 24
Inquirex::SafeSource.validate(source, max_bytes: 8_192, max_depth: 12) # or per call
```

Gems that extend the DSL register their own vocabulary at boot rather than forking the allowlist:

```ruby
V = Inquirex::SafeSource::Vocabulary
V.register_scope(:llm_step, label: "an LLM step",
  vocabulary: -> { Inquirex::LLM::DSL::StepBuilder.public_instance_methods(false) })
V.allow(:flow, :clarify, positional: %i[symbol], block: :llm_step)
V.allow(:llm_step, :prompt, positional: %i[literal])
V.exclude(:llm_step, :fallback, "a Ruby block cannot be validated")
```

Until a gem does that, its verbs are rejected in safe mode — load such flows with `unsafe: true`, or register the vocabulary yourself. The `vocabulary:` binding is what lets `Vocabulary.undeclared_names(scope)` report DSL words that have no allowlist decision; this gem's own suite fails the build when that list is non-empty, and hosts can assert the same at boot.

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
- `UnsafeSourceError` (a `DefinitionError`; carries `#violations`)
- `UnknownStepError`
- `SerializationError`
- `AlreadyFinishedError`
- `ValidationError`
- `NonCollectingStepError`
- `RequiredStepError`

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

## License

MIT. See [`LICENSE.txt`](LICENSE.txt).

© 2026 Konstantin Gredeskoul.

0
