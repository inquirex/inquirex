## [Unreleased]

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
