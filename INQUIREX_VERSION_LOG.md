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

### Consumer catch-up for `required false` (shipped in the gem at 0.7.0)

The gem has had optional steps since 0.7.0. Nothing downstream implements them yet:

- `@kigster/inquirex-js` — no Skip control; `"required": false` is ignored.
- `inquirex-webui` — the DSL printer does not emit the setter, so a visual save silently strips it.
- ~~**qualified.at** — `SafeDsl::Validator` does not allowlist `required`.~~ **Fixed 2026-08-01.** The validator now carries `required: CallSpec.new(positional: { optional: :literal })` in `STEP_CALLS`, matching the gem's `required(value = true)` signature so bare `required` is accepted alongside `required false`. Until that ships, a flow using the verb is **rejected**, not degraded — the validator is default-deny and runs on read as well as write, so it takes down flows that were already saved.

### Planned

- Top-left and top-right widget placement (`@kigster/inquirex-js`) — `WidgetPosition` widens from `bottom-right | bottom-left` to all four corners, with `:host([position="top-*"])` rules for the host element, the panel, and the debug panel.

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
