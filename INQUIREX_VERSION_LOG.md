# Inquirex family version log

Hand-written. This is the one document that answers **"what changed across the whole family in version X?"**

It covers the four lockstep packages, which share a version number because they share a serialization format:

| Package           | Registry | Role                              |
| ----------------- | -------- | --------------------------------- |
| `inquirex`        | RubyGems | Defines the DSL and the step JSON |
| `inquirex-llm`    | RubyGems | Extends the DSL vocabulary        |
| `inquirex-widget` | npm      | Renders the step JSON to a lead   |
| `inquirex-webui`  | npm      | Prints the step JSON back to DSL  |

> `inquirex-widget` was published as `@kigster/inquirex-js` through 0.8.0; the npm package was renamed (same runtime, byte-identical dist). The GitHub repo is still `inquirex/inquirex-js`.

A verb added to one and missing from another does not fail loudly — it silently drops data. The `required false` history below is exactly that: the gem shipped it in 0.7.0 and no consumer knew, so the visual builder would strip it on save and qualified.at's allowlist rejects it outright.

`inquirex-tty` is **not** in the lockstep set. It is a developer tool outside the wire contract and versions independently.

Check parity with `bin/inquirex-version` in the ecosystem root; `--set X.Y.Z` moves all four; `--preflight` reports release readiness.

> **This file is curated, not generated.** Each package's own `CHANGELOG.md` is produced by `github_changelog_generator` from merged PRs, which captures *what* merged but not *why it matters* or *what a consumer must do about it*. Both are wanted; only this one survives a regeneration.

______________________________________________________________________

## [Unreleased]

### SECURITY: `load_dsl` validates before it evaluates (`Inquirex::SafeSource`)

`Inquirex.load_dsl(text)` was a bare `eval`. Every host passing customer-authored text to it handed that customer arbitrary Ruby in the loading process — confirmed live downstream, where the chain was open signup → org admin → DSL editor → RCE in the production container, re-executing on every visitor because the app memoizes at request time. The vulnerability is in this gem's API, so the fix belongs here.

- **`Inquirex::SafeSource`** — a default-deny **Prism AST allowlist** (Prism is stdlib on Ruby >= 4.0, so no new dependency). It walks the source by recursive descent *against the shape the DSL produces* rather than blocklisting method names, so a construct nobody anticipated is rejected by construction. Public API: `SafeSource.validate(text)` → violations, `.safe?`, `.validate!`. Caps at 64 KiB and 24 levels of nesting, all overridable.
- **`Inquirex.load_dsl(text, unsafe: false, max_bytes:, max_depth:)`** — validation runs **before** the eval; the ordering is the whole fix. `unsafe: true` is the escape hatch for source you author (a `.rb` file, a fixture, the file `inquirex-tty` was pointed at), named so the dangerous call is the conspicuous one.
- **`Errors::UnsafeSourceError < Errors::DefinitionError`** carrying `#violations`, so existing host `rescue DefinitionError` clauses keep working and a payload reads as "invalid DSL" rather than a 500.
- **The allowlist is bound to the DSL, not hand-copied from it**: flow verbs come from `Node::VERBS`, types from `Node::TYPES`, rules from `DSL::RuleHelpers`, email fields from one `EMAIL_FIELD_KEYWORDS` table serving both the inline and block forms. `vocabulary_spec` fails the build when a builder gains a public method that is neither allowed nor excluded. Downstream gems extend rather than fork via `Vocabulary.register_scope` / `.allow` / `.exclude`.
- **Deliberate exclusion**: `compute` (a block is arbitrary Ruby, indistinguishable from a payload). Available under `unsafe: true` only. `action`, `run`, `webhook`, `allowed_domains` and the `{ file: "path" }` body form need no exclusion — they were deleted outright (below), which is the stronger guarantee.

Ported from PR #5, adapted to the post-actions DSL. Suite: **861 examples, 0 failures**, coverage 97.17%.

Consumer obligations:

- **qualified.at** — replace `app/services/safe_dsl.rb` + `safe_dsl/validator.rb` with `Inquirex::SafeSource`; the hand-copied allowlist is now stale twice over (it still carries `action` and `allowed_domains`). `spec/security/no_direct_dsl_eval_spec.rb` should assert the guarded call rather than banning `load_dsl` outright, and `rake qualifiers:audit_dsl` can call `SafeSource.validate` directly. Note `inquirex-tty` and any `.rb` fixture loading must pass `unsafe: true`.
- **inquirex-llm** — register its vocabulary (`extract`/`clarify`, `prompt`, `schema`, `from`, `from_all`, `model`, `temperature`, `max_tokens`, and `fallback` as an exclusion) or flows using those verbs are rejected in safe mode.

### BREAKING: post-completion actions are gone; `send_email` is a top-level DSL verb

The actions framework (0.6.0) is removed from the gem. Post-completion behavior — webhooks, custom code, delivery orchestration — is the **host application's** job (qualified.at already owns lead delivery via `LeadMailer` and `SiteWebhook`); carrying a second execution framework inside the flow definition duplicated it with a worse security story.

What the DSL loses and gains:

- **Removed verbs**: `action`, `run`, `webhook`, `allowed_domains`. Stored DSL using any of them now fails to load (`action` raises `NoMethodError`, wrapped into `DefinitionError` by `Inquirex.load_dsl`). There is no deprecation shim — versions only go forward.
- **New verb**: top-level `send_email`, a *declaration, not an action*. Block-builder form (`to "{{email}}"`, `from`, `cc`, `bcc`, `reply_to`, `subject`, `headers`, `text`, `markdown_text`, `html`) and inline keyword form; optional `if:` rule gate using the same serializable AST as transitions.
- **New body field `markdown_text`**: carried as Markdown on the wire; the gem never renders Markdown to HTML (zero-dependency rule) — hosts render it.

Wire format change: the top-level `"actions"` array (with `"effects"` and `"type"` tags) is replaced by `"send_emails"` — a flat array of email objects, each with optional `"if"`. The `"allowed_domains"` key is gone. Old JSON with `"actions"` is silently ignored by `Definition.from_h` (unknown keys are dropped), so rehydrating a pre-change definition loses its actions rather than failing — audit stored definitions before upgrading.

Ruby API change: `Inquirex::Actions::*` (Action, Runner, Outbox, registry, effects) is deleted. `Inquirex::SendEmail` (with `#applicable?` and `#to_mail`) and `Inquirex::Template` replace `Actions::SendEmail` / `Actions::Template`. `Answers#outbox` is removed. `Errors::ActionError` is renamed `Errors::SendEmailError`. `Definition#actions` / `#allowed_domains` / `#allowed_host?` are gone; use `Definition#send_emails`.

Consumer obligations:

- **qualified.at** — `SafeDsl::Validator` must drop `action` + `allowed_domains` from the allowlist and accept top-level `send_email` with its builder words and `if:` (literal arguments only, as ever). Run `rake qualifiers:audit_dsl` against production first: any stored flow using `action` must be migrated before this gem version deploys, because the validator runs on read and takes down saved flows.
- **inquirex-webui** — the printer must emit the `send_email` block form; it never emitted `action`, so nothing to remove.
- **inquirex-widget** — `"send_emails"` is server-side data; the widget must tolerate (ignore) the key. The old `"actions"` key was equally ignored, so no change is expected — verify, don't assume.

### `optional` — the inverse spelling of `required` (DSL sugar, no wire change)

Steps are required by default, so `required true` was always a no-op and the keyword only ever appeared as `required false`. Its entire purpose was to express optionality, through a negation. `optional` says the same thing directly:

```ruby
ask :dependents do
  type :integer
  question "How many dependents?"
  optional          # identical to `required false`
  default 0
end
```

- **Sugar only, deliberately.** Both spellings set the same field and serialize to the same single wire key, `"required": false`. `to_h` output is byte-identical either way, and a spec asserts it. Two DSL words, one wire representation — a second key would be a new thing for four packages to keep in sync, which is the failure mode this document exists to catch.
- **`optional false` means required**, for symmetry. Prefer `required` for that; the double negative is what `optional` was added to avoid.
- **Contradictions raise.** `required true` alongside `optional true` is an `Errors::DefinitionError` rather than last-call-wins. Agreeing duplicates (`required false` plus `optional`) are tolerated.
- Allowlisted in `SafeSource::Vocabulary` for the `:step` scope, so stored DSL may use it.

Consumer obligations:

- **qualified.at** — `SafeDsl::Validator` must allowlist `optional` with the same shape as `required` (`positional: { optional: :literal }`, so bare `optional` and `optional true` both pass). **This is the `required false` incident repeating**: the validator is default-deny and runs on read as well as write, so a flow using the verb is rejected outright rather than degraded — taking down flows that were already saved. Allowlist it before this gem version deploys, not after.
- **inquirex-webui** — the printer should emit `optional` as the canonical spelling for a skippable step. Because the wire format is unchanged, a flow authored as `required false` will print back as `optional`; that is a deliberate normalization to the clearer form, not data loss.
- **inquirex-widget** — no change. The wire key it already reads is untouched, which is the whole point of keeping one representation.

### Consumer catch-up for `required false` (shipped in the gem at 0.7.0)

The gem has had optional steps since 0.7.0. Nothing downstream implements them yet:

- `inquirex-widget` — no Skip control; `"required": false` is ignored.
- `inquirex-webui` — the DSL printer does not emit the setter, so a visual save silently strips it.
- ~~**qualified.at** — `SafeDsl::Validator` does not allowlist `required`.~~ **Fixed 2026-08-01.** The validator now carries `required: CallSpec.new(positional: { optional: :literal })` in `STEP_CALLS`, matching the gem's `required(value = true)` signature so bare `required` is accepted alongside `required false`. Until that ships, a flow using the verb is **rejected**, not degraded — the validator is default-deny and runs on read as well as write, so it takes down flows that were already saved.

### Extraction prefill: form-value matching and auto-skip (behavior change, all runtimes)

The `prompt :auto` field report — "LLM returned `us_person`, yet the question was asked again and the wrong option appeared selected; `W2` came back but wasn't pre-checked" — exposed three gaps, fixed in lockstep:

- **`inquirex` (engine)**: a collecting step whose answer already exists is never asked again — `Engine#skip_if_needed` now skips answered steps, so extraction collapses the form **without** authors hand-writing `skip_if not_empty(:self)` on every question. `Engine#prefill!` canonicalizes values for option steps via the new `Node#resolve_option`: exact form-value match, then case-insensitive value, then case-insensitive **label → value** (matching always resolves to the form value, never the label); unmatchable values are dropped, so junk can neither preselect a wrong option nor satisfy `not_empty`. Prefilled answers now feed accumulators like typed ones. Multi-select extractions remain suggestions (asked, pre-checked).
- **`inquirex-llm` (adapters)**: `Adapter#normalize_output` runs on every parsed response — value-constrained schema fields are canonicalized case-insensitively against the allowed values; anything outside the list becomes nil (enum) or is dropped (multi_enum), i.e. "unknown, will ask" instead of junk.
- **`inquirex-widget`**: `applyExtraction` gains the same canonicalization; multi-select extractions now land in a new `suggestions` channel (pre-checked in `iq-multi-enum` via the `initial` property, question still asked) instead of silently skipping the question; answered steps auto-skip; skip transitions are resolved by rule evaluation (Ruby parity) instead of "last transition".
- **`inquirex-tty`** (independent version): `Renderer#render` accepts `suggestion:` and pre-checks `multi_select` choices via tty-prompt `default:` (labels); the `run` command threads `Engine#suggestion_for` through.

Consumer note for **qualified.at**: `WizardController` already routes extraction through `Engine#prefill!`, so it inherits the engine fixes on the next gem bump; verify the ERB `:multi_enum` branch keeps using `suggestion_for` (it does today) and that no flow relied on junk extractions skipping questions.

### Planned

- Top-left and top-right widget placement (`inquirex-widget`) — `WidgetPosition` widens from `bottom-right | bottom-left` to all four corners, with `:host([position="top-*"])` rules for the host element, the panel, and the debug panel.

______________________________________________________________________

## [0.9.5] - 2026-08-06

### Numeric steps can declare bounds: `min`, `max`, `step_size`

An `:integer`, `:decimal` or `:currency` step can now state the range it accepts. Three new step-level DSL keywords, three new wire fields, and one new guarantee.

```ruby
ask :employees do
  type :integer
  question "How many employees?"
  min 0
  max 500
  step_size 5
  transition to: :done
end
```

- **Wire format** gains `"min"`, `"max"`, `"step_size"` on collecting steps. All three are omitted when unset, so every existing definition serializes byte-identically and the change is additive.
- **`step_size`, not `step`** — a step *is* the unit of a flow, and `steps.employees.step` would read as a nested flow step rather than a stepper increment.
- **`Node#clamp(value)`** is the enforcement point, and it is the reason this is not merely presentational. `min`/`max` on an HTML number input bound the stepper arrows and flip `:out-of-range`; they do **not** stop a visitor typing or pasting `900` into a 1–10 field, and an LLM extraction has no notion of a bound at all. Anything that stores an answer for a bounded step should clamp.
- **`Node#bounded?`** predicate, and `Node::BOUNDED_TYPES` (`%i[integer decimal currency]`).
- **Bounds are validated at build time, not ignored.** A bound on a non-numeric type, a non-`Numeric` bound, and `min > max` each raise `Errors::DefinitionError`. Declaring `min 1` on a `:string` almost always means the author picked the wrong type; failing loudly is cheaper than shipping it.
- **Registered in `SafeSource::Vocabulary`** as `:literal` positionals — the same value kind `default` already accepts. Nothing executable becomes expressible. This registration is the part that made 0.7.0's `required false` unusable when it was missed; see the note at the top of this file.

Consumer state at release — all four lockstep packages ship it:

| Package           | What it does with the bounds                                              |
| ----------------- | ------------------------------------------------------------------------- |
| `inquirex`        | Declares, validates, serializes, and clamps                               |
| `inquirex-widget` | Renders `min`/`max`/`step` on the field; clamps in `getValue()`           |
| `inquirex-webui`  | Prints them back to DSL; Inspector edits them; clears them on type change |
| `inquirex-llm`    | Unaffected — bounds are not part of an extraction schema                  |

`inquirex-tty` (outside lockstep) passes them to `TTY::Prompt`'s `in:`, which re-asks until the answer is in range.

Consumer obligations:

- **qualified.at** — none required. Its `SafeDsl::Vocabulary` *extends* the gem's table rather than forking it, so the new keywords are inherited; `spec/services/safe_dsl_spec.rb` now pins that inheritance so a future fork breaks the build instead of a customer's saved flow. Bump the Gemfile pins to `~> 0.9.5` and re-sync the vendored `inquirex-webui` bundle (`just webui-sync`) and `vendor/inquirex-js/inquirex.min.js`.
- **Any host storing answers itself** — route numeric answers through `Node#clamp`. The bound is not self-enforcing on the client.
- **Visual builders other than `inquirex-webui`** — model all three fields, or the printer will silently delete an author's bounds on the next save. This is the `required false` failure mode exactly.

### `inquirex-widget`: numeric fields look and behave numeric

- **Stepper arrows are visible again.** The component had been suppressing them outright (`-moz-appearance: textfield` plus `-webkit-appearance: none` on the spin buttons), so a numeric field was indistinguishable from a text box. WebKit's hover-only default is overridden too, so the affordance is visible before the field is touched.
- **Out-of-range is shown, then corrected.** Typing past a bound warns (native `:out-of-range` styling plus a hint) but does not rewrite mid-keystroke — typing `15` into a 10–20 field passes through `1`, and snapping that to the minimum would make the field impossible to fill. The clamp commits on `change` (blur or an arrow click), so the stored value is the visible one.
- **A display step's Continue button now takes focus**, which restores Enter *and* Space through native button activation rather than a bespoke key handler, and makes the step reachable by Tab and screen reader. A `say` / `header` / `btw` / `warning` step renders no input, so nothing had been focused and Enter did nothing at all. The multiline Continue is deliberately excluded — focusing it would pull the caret out of the textarea.
- **The widget retires itself after a completed flow.** Once the completion checkmark has been on screen for `auto-dismiss-ms` (default 3500), the whole element — launcher included — fades over 1.2s and then renders nothing. Set `auto-dismiss-ms="0"` to keep the finished panel up. A `summarize` flow is exempt: its closing screen carries the summary plus Close and Print, and pulling that out from under a reader would destroy what the flow just produced. `prefers-reduced-motion` collapses the fade.

______________________________________________________________________

## [0.7.0] - 2026-07-21

- `required false` DSL builder method on collecting steps (`ask`, `confirm`): marks a question as optional so widgets render a small Skip control. Default remains `required true`, so every existing flow is unchanged.
- `Node#required?` predicate; step JSON gains `"required": false` (omitted when true), round-tripping through `to_json` / `from_json`.
- `Engine#skip` — user-initiated skip of the current optional step: records the step's `default` (when declared) into the answers and accumulators exactly as if answered, marks the step id in the new `Engine#skipped` list, and advances through transitions like `#answer`. Raises `Errors::RequiredStepError` (new) on a required step, `NonCollectingStepError` on a display step.
- Skip without a default writes no answers entry (a missing key and `nil` branch identically in rules; the "declined" signal lives in `skipped`).
- `Engine#skipped` / `Engine#skipped?(step_id)` distinguish default-by-skip values from user-provided answers; the list survives `to_state` / `from_state` (string→symbol normalized) and is merged into `Engine#answers_with_metadata` under `:skipped`.
- Steps elided automatically by `skip_if` rules are NOT marked as skipped — auto-elision is flow logic, `#skip` is a user action (see docs/design/required-and-skip.md).

## [0.6.0] - 2026-07-19

- Post-completion `action` DSL verb with an extensible effect registry
- `send_email` effect: builds `Mail::Message` objects (multipart text/HTML) from `{{field}}` templates into `Answers#outbox`; delivery is the host application's responsibility. The `mail` gem is a soft dependency.
- `run { |answers, outbox| ... }` escape-hatch effect (stripped from JSON)
- `webhook` effect: POSTs the answers envelope to a static https URL whose host must be covered by the new top-level `allowed_domains` declaration; enforcement runs in `Definition#validate!`, so tampered JSON definitions fail at rehydration
- `Inquirex::Actions::Runner` and `Inquirex::Actions.run(definition, answers)`
- Actions serialize to/from JSON with their rule gates
- `CompletionMetadata` (OpenStruct; `engine` and `engine_version` required) stamped by the engine at flow completion, enrichable by front-ends via the new `Engine#after_completion` hook, persisted in engine state, and merged into answers by `Engine#answers_with_metadata`

## [0.1.0] - 2026-04-13

- Initial release

______________________________________________________________________

## Version history before lockstep

The four packages versioned independently until 0.8.0. Their last independent releases:

| Package                                        | Last independent version |
| ---------------------------------------------- | ------------------------ |
| `inquirex`                                     | 0.7.0                    |
| `inquirex-llm`                                 | 0.6.0                    |
| `@kigster/inquirex-js` (now `inquirex-widget`) | 0.4.0                    |
| `inquirex-webui`                               | 0.1.0                    |

0.8.0 is the first lockstep release — the first number above every one of them, since versions only ever go forward.
