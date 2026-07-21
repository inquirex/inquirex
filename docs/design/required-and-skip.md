# Design: `required false` and user-initiated `Engine#skip`

Status: implemented in 0.7.0

## Problem

Every collecting step (`ask`, `confirm`) currently demands an answer — the only way past a question without answering it is an automatic `skip_if` rule baked into the definition. Flow authors want to mark individual questions as *optional*: the widget renders a small **Skip** button, and a lead who declines the question moves on. When the step declares a `default`, that default should land in the answers so downstream rules and accumulators behave deterministically — but it must remain distinguishable from a value the lead actually typed.

## DSL surface

`required` is a builder method inside `ask` / `confirm` blocks, exactly like `default` and `skip_if`:

```ruby
ask :dependents do
  type :integer
  question "How many dependents?"
  required false          # renders a Skip button; default is required (true)
  default 0               # what a skip records into answers
  transition to: :done
end
```

Decisions:

- **Builder-method form only.** This DSL configures steps exclusively through builder methods inside the block (`type`, `question`, `default`, `skip_if`, ...); the flow verbs themselves (`ask :id do ... end`) accept no option hash anywhere in the grammar. An `ask :dependents, required: false` option-hash form would be the first of its kind, so it is deliberately not offered.
- **Default is `required(value = true)`.** Bare `required` reads as an explicit assertion of the default; `required false` is the interesting call. Every existing flow is unchanged.
- `required false` on a display verb (`say`, `header`, `btw`, `warning`) is accepted and ignored, consistent with the DSL's permissive treatment of irrelevant builder calls (e.g. `question` inside `say`). `Engine#skip` on a display step fails on the collecting-step check before optionality is ever consulted.

## Node and serialization

- `Node.new` gains `required: true`; the value is normalized to a strict boolean.
- `Node#required?` — public predicate, `true` by default.
- Wire format: step JSON gains `"required": false`, **omitted when true** — the same omit-the-default convention used by `"requires_server"` (omitted when false) and `"default"` (omitted when nil). Emitted only for collecting steps.
- `Node.from_h` uses a fetch chain (not `||`) so an explicit `false` survives; absent key means `true`. Round-trips through `Definition#to_json` / `.from_json`.

## Engine: `#skip`

Named `skip` (no bang) to sit beside its peers `answer` and `advance` — the three user-driven step actions. (`prefill!` keeps its bang because it is a bulk out-of-band mutation, not a step action.)

```ruby
engine.skip
# => records default (if any), marks the step skipped, advances transitions
```

Semantics, in order:

1. Raises `Errors::AlreadyFinishedError` when the flow is finished.
1. Raises `Errors::NonCollectingStepError` on a display step (use `#advance`).
1. Raises `Errors::RequiredStepError` (new, `< EngineError`) when `Node#required?` is true.
1. Resolves the step's `default` — a `Proc` default is called with the answers collected so far, exactly as a renderer pre-filling the field would resolve it.
1. **With a default**: the default is recorded into `answers[step_id]` and contributes to accumulators, exactly as if the lead had submitted it. The default *is* the answer; only its provenance differs.
1. **Without a default: no answers entry is written** (not even `nil`). Rationale: rules read `answers[field]`, so a missing key and an explicit `nil` branch identically — but an explicit `nil` would flip `Hash#key?`, satisfy "was this collected?" checks in consumers, and contradict `prefill!`'s established stance that nil is not a fact. The "lead declined" signal lives in `skipped`, not in a sentinel value.
1. Any prefill suggestion for the step is discarded (the step is resolved), and the engine advances through transitions exactly like `answer` — rules evaluate against whatever value landed (the default, or nothing).

## The `skipped` channel

`engine.skipped` — an ordered, duplicate-free `Array<Symbol>` of user-skipped step ids, plus a `skipped?(step_id)` predicate. It follows the `suggestions` state pattern end to end: initialized in `initialize`, restored in `restore_state`, emitted by `to_state`, and normalized (strings → symbols) by a `StateSerializer::SYMBOLIZERS` entry, so it survives JSON round-trips of persisted sessions.

`answers_with_metadata` merges `skipped: [...]` alongside `completion_metadata` when any step was skipped, so post-completion actions (webhooks, email templates) and the qualified.at lead record can distinguish defaulted-by-skip values from typed answers without a second API.

## `skip_if` vs user skip: distinct concepts

- `skip_if` is **flow logic**: the definition elides a step from the path (auto-skip). No answer is recorded, no default kicks in, and — decision — the step does **not** enter `skipped`. It was never presented, so the lead cannot have declined it.
- `Engine#skip` is a **user action**: the lead saw an optional question and declined it.

Conflating the two would pollute the "declined" signal (drop-off analytics, lead-quality scoring) and retroactively change the state shape of every existing `skip_if` flow. Documentation says "auto-skip" / "elided" for `skip_if` and "skip" for the user action.

## Consumer contract (qualified-at wizard, inquirex-js)

- Render a small **Skip** control on any collecting step whose JSON carries `"required": false` (absence of the key means required).
- Skip control activated → call `Engine#skip` (Ruby hosts) or perform the equivalent local bookkeeping (JS): record the step's `"default"` (when present) as the answer, add the step id to the session's `skipped` list, evaluate transitions as usual.
- On submission, `skipped` travels with the answers (`answers_with_metadata`), letting the backend mark those values as defaults-by-skip rather than lead-provided facts.

## Out of scope

- Rendering of the Skip button (consumers).
- Back-navigation un-skipping; the engine has no back primitive today.
- Treating `skip_if`-elided steps as skipped (explicitly decided against, above).
