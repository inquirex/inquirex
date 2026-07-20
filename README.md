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

***Don't want to deal with figuring it out? Head to [Qualified.At](https://qualified.at/onboarding) and walk through the demo onboarding form, that exists specifically to show you how quickly you can have the same conceptually on your site, tailored to YOUR users.***

## Summary

This one is the core gem in the Inquirex ecosystem that focuses on:

- A conversational DSL (`ask`, `say`, `header`, `btw`, `warning`, `confirm`)

- A serializable AST rule system (`contains`, `equals`, `greater_than`, `less_than`, `not_empty`, `all`, `any`)

- Framework-agnostic widget rendering hints (`widget` DSL verb, `WidgetHint`, `WidgetRegistry`)

- Named ***accumulators*** for running totals (pricing, complexity scoring, credit scoring, lead qualification)

- An immutable flow definition graph

- A runtime engine for stateful step traversal

- JSON round-trip serialization for cross-platform clients

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

## Completion Metadata

When a flow finishes, the engine guarantees a `CompletionMetadata` — an
OpenStruct describing how the answers were collected. Only `engine` and
`engine_version` are required members; rendering front-ends attach richer
environment details from an `after_completion` hook:

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

If no hook supplies one, the engine stamps the minimal core version
(`engine: "inquirex"`, `engine_version: Inquirex::VERSION`). The metadata
persists through `Engine#to_state` / `Engine.from_state`, and
`engine.answers_with_metadata` merges it into the answers hash under
`:completion_metadata` — which also makes it available to post-completion
actions: webhook payloads carry it, and email templates can interpolate
`{{completion_metadata.engine}}`.

## Post-Completion Actions

After all questions are answered, `action` declarations run server-side with
the collected answers. The flagship effect is `send_email`, which **builds**
`Mail::Message` objects (the same object ActionMailer wraps) and attaches them
to `answers.outbox` — **nothing is delivered**; the host application decides
how and when to send.

```ruby
Inquirex.define id: "tax-intake-2025" do
  allowed_domains "*.agentica.group"   # egress allowlist for webhook effects

  # ... ask steps ...

  action :client_receipt, if: not_empty(:email) do
    send_email to:      "{{email}}",
               from:    "forms@agentica.group",
               subject: "Thanks {{name}} — we received your intake",
               text:    <<~TEXT,
                 Hi {{name}},
                 We received your answers:

                 {{answers_summary}}
               TEXT
               html:    <<~HTML
                 <p>Hi {{name}},</p>
                 <img src="https://cdn.agentica.group/logo.png" alt="Logo">
                 {{answers_summary}}
               HTML
  end

  action :admin_alert do
    send_email to: "owner@agentica.group", from: "forms@agentica.group",
               subject: "New lead: {{name}} <{{email}}>",
               html: "{{answers_summary}}"
    run { |answers, outbox| Metrics.count(:lead, answers.to_flat_h) }
  end

  action :crm_push do
    webhook url: "https://hooks.agentica.group/inquirex",
            headers: { "X-Api-Key" => "..." }
  end
end
```

Execution and delivery:

```ruby
answers = Inquirex::Actions.run(definition, engine.answers)
answers.outbox.messages   # => [Mail::Message, ...]
answers.outbox.results    # => per-action :ok / :skipped / :failed trail

# In a Rails host:
answers.outbox.each do |message|
  ActionMailer::Base.wrap_delivery_behavior(message)  # adopt Rails delivery config
  message.deliver
end
```

Key semantics:

- **Templating is `{{field}}` interpolation only** — dot-notation keys resolved
  against `Answers#to_flat_h`, deliberately inert (no code execution), so
  definitions stored in a database render safely. Values interpolated into
  `html:` bodies are HTML-escaped automatically; `text:` bodies stay verbatim.
  The built-in `{{answers_summary}}` expands to all collected answers.
- **`if:` gates** reuse the serializable rule AST (`not_empty(:email)`, ...).
  A false rule records `:skipped` — declare no actions (or gate them) when a
  flow should only save answers.
- **`run { |answers, outbox| ... }`** is the full-Ruby escape hatch; like all
  lambdas it is stripped from JSON.
- **Failures are isolated**: a raising effect records `:failed` in
  `outbox.results` and never blocks other actions.
- **Images** in HTML bodies must be external URLs; attachments are unsupported.
- The `mail` gem is a soft dependency, needed only when a message is built
  (Rails hosts already have it via ActionMailer).
- **`webhook url:`** POSTs `{"answers": {...}}` as JSON to a static URL. The
  URL's host must be covered by `allowed_domains`, declared at the top of the
  definition so the flow's egress surface is auditable at a glance. The check
  runs inside `Definition.new` — a JSON definition whose webhook URL was
  tampered with fails at *rehydration*, before anything executes. Also
  enforced: https only (plain http just for localhost), no userinfo, no
  `{{field}}` templates in URLs (the destination must be static), redirects
  are not followed, and non-2xx responses record `:failed`.
- Effects are extensible: `Inquirex::Actions.register(:save_record, MyEffect)`
  gives a new verb both DSL and JSON wire support.

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
- Post-completion actions (`actions`) with their rules and effects; `run`
  blocks are stripped, and an action left with no serializable effects is
  omitted entirely
- The `allowed_domains` egress allowlist, re-enforced against webhook URLs
  every time a definition is rehydrated

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

## License

MIT. See [`LICENSE.txt`](LICENSE.txt).

© 2026 Konstantin Gredeskoul.

0
