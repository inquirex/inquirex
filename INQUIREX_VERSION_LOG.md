# Inquirex family version log

Hand-written. This is the one document that answers **"what changed across the whole family in version X?"**

It covers the four lockstep packages, which share a version number because they share a serialization format:

| Package                | Registry | Role                              |
| ---------------------- | -------- | --------------------------------- |
| `inquirex`             | RubyGems | Defines the DSL and the step JSON |
| `inquirex-llm`         | RubyGems | Extends the DSL vocabulary        |
| `@kigster/inquirex-js` | npm      | Renders the step JSON to a lead   |
| `inquirex-webui`       | npm      | Prints the step JSON back to DSL  |

A verb added to one and missing from another does not fail loudly — it silently drops data. The `required false` history below is exactly that: the gem shipped it in 0.7.0 and no consumer knew, so the visual builder would strip it on save and qualified.at's allowlist rejects it outright.

`inquirex-tty` is **not** in the lockstep set. It is a developer tool outside the wire contract and versions independently.

Check parity with `bin/inquirex-version` in the ecosystem root; `--set X.Y.Z` moves all four; `--preflight` reports release readiness.

> **This file is curated, not generated.** Each package's own `CHANGELOG.md` is produced by `github_changelog_generator` from merged PRs, which captures *what* merged but not *why it matters* or *what a consumer must do about it*. Both are wanted; only this one survives a regeneration.

______________________________________________________________________

## [Unreleased]

### Consumer catch-up for SafeSource and `send_email` (pending merge to `inquirex`)

The gem's PR #5 adds `SafeSource` (load-time DSL validation) and the top-level `send_email` verb. Nothing downstream implements them yet:

- **qualified.at** — replace `SafeDsl` service with `Inquirex::SafeSource`; add `CompletionActionsJob` to process `Engine#on_complete_actions`.
- **inquirex-webui** — add the `send_email` verb to the `Verb` union, `printDsl`, stencils, and the highlighter keyword list; `lintDefinition`'s `unknown_field` code is the natural home for `template_warnings`.
- **inquirex-llm** — register LLM vocabulary (`extract`, `clarify`, `prompt`, `schema`, `model`, `temperature`, `max_tokens`) via `SafeSource::Vocabulary.register_scope` / `allow` / `exclude`.

### Consumer catch-up for `required false` (shipped in the gem at 0.7.0)

The gem has had optional steps since 0.7.0. Nothing downstream implements them yet:

- `@kigster/inquirex-js` — no Skip control; `"required": false` is ignored.
- `inquirex-webui` — the DSL printer does not emit the setter, so a visual save silently strips it.
- ~~**qualified.at** — `SafeDsl::Validator` does not allowlist `required`.~~ **Fixed 2026-08-01.** The validator now carries `required: CallSpec.new(positional: { optional: :literal })` in `STEP_CALLS`, matching the gem's `required(value = true)` signature so bare `required` is accepted alongside `required false`. Until that ships, a flow using the verb is **rejected**, not degraded — the validator is default-deny and runs on read as well as write, so it takes down flows that were already saved.

### Planned

- Top-left and top-right widget placement (`@kigster/inquirex-js`) — `WidgetPosition` widens from `bottom-right | bottom-left` to all four corners, with `:host([position="top-*"])` rules for the host element, the panel, and the debug panel.

______________________________________________________________________

## [0.8.0] - pending

### `inquirex`: SafeSource DSL validation and the `send_email` verb

#### `Inquirex.load_dsl` now validates before it evaluates (breaking)

`Inquirex.load_dsl(text)` was a bare `eval` with no validation. Any host that passed user-supplied text to it handed that user arbitrary Ruby execution. This was confirmed live in a downstream Rails app: a backtick payload wrote a file and `ENV` was fully readable.

- **New:** `Inquirex::SafeSource` — a default-deny Prism AST allowlist. Public API: `SafeSource.validate(text)`, `.safe?(text)`, `.validate!(text)`. Use it to audit stored definitions without evaluating them.
- **New:** `Inquirex::Errors::UnsafeSourceError < Inquirex::Errors::DefinitionError`, carrying `#violations`. Existing `rescue DefinitionError` clauses keep working.
- **New:** `Inquirex::SafeSource::Vocabulary` — the allowlist bound to its builders. `Vocabulary.undeclared_names(scope)` reports DSL words with no allowlist decision; the test suite fails when non-empty. Downstream gems extend it with `register_scope` / `allow` / `exclude`.
- **Changed:** `Inquirex.load_dsl(text, unsafe: false, max_bytes:, max_depth:)`. Validation is on by default.
- **Breaking:** flows that use `compute`, a block-form `default` or `fallback` no longer load through the default path. Pass `unsafe: true` for source you control as code (a developer-authored `.rb` file, a fixture).
- Caps: 64 KiB of source and 24 levels of nesting (overridable).

#### New: the top-level `send_email` verb (breaking)

A flow now declares the email it wants sent as a first-class part of the definition:

```ruby
send_email do
  to      "{{ answers.email }}"
  from    "Qualified.At"
  subject "Thank you for filling the form"
  body_markdown <<~'TEXT'
    Dear {{ answers.name }}, your total is ${{ accumulators.price | round: 2 }}.
  TEXT
end
```

- **New:** `Inquirex::Email` — four opaque Liquid template strings (`to`, `from`, `subject`, `body_markdown`), serialized under `"emails"` and rehydrated by `from_json`.
- **The gem declares, the host renders.** `Email` never renders templates, never converts Markdown, never builds a `Mail::Message`.
- **New:** `Engine#on_complete_actions` — plain, JSON-serializable Hashes including a `"context"` snapshot so entries can be enqueued and processed independently of the engine.
- **New:** `Engine#render_context` — the `{"answers", "accumulators"}` Hash a host binds when rendering. Fetch at display time; symbol keys and values normalized to Strings for queue round-trips.

#### New: Liquid placeholders in every user-facing string

`question`, `text`, and every `send_email` field may carry `{{ }}` references to earlier answers and accumulator totals. **`{{ }}` is data; `#{}` is Ruby and stays forbidden.**

- **New:** `Inquirex::TemplateRefs` and `Definition#template_warnings` — names references that resolve to nothing. Advisory, not fatal.

#### Removed: the dangerous action effects (breaking)

Deleted outright — no `unsafe: true` brings them back:

- **`webhook` effect and `allowed_domains`** — destination self-authorized by the untrusted document; plain `http` to localhost was permitted (SSRF).
- **`run { |answers, outbox| ... }` and `Actions::Custom`** — arbitrary Ruby.
- **`send_email text:`/`html:` given as `{ file: "path" }`** — arbitrary file disclosure.

`Actions::Base#serializable?`, `Actions::Action#serializable?`, `Definition#allowed_host?`, and `Definition#allowed_domains` are gone. `Definition#to_h` no longer filters actions.

#### Deprecated: the `action` verb

`action ... do send_email ... end` still parses and runs. Deprecated in 0.8.0; removal is 0.9.0.

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

| Package                | Last independent version |
| ---------------------- | ------------------------ |
| `inquirex`             | 0.7.0                    |
| `inquirex-llm`         | 0.6.0                    |
| `@kigster/inquirex-js` | 0.4.0                    |
| `inquirex-webui`       | 0.1.0                    |

0.8.0 is the first lockstep release — the first number above every one of them, since versions only ever go forward.
