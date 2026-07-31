## [Unreleased]

## [0.7.0] - 2026-07-30

### `Inquirex.load_dsl` now validates before it evaluates (breaking)

`Inquirex.load_dsl(text)` was a bare `eval` of whatever it was handed. Any host that passed user-supplied text to it — a database column a customer edits, an upload, LLM output, a visual builder's "sync" button — was handing that user arbitrary Ruby execution in the loading process. This was confirmed live in a downstream Rails app: a backtick payload wrote a file and `ENV` was fully readable, and because the app memoised `load_dsl` per request, a stored payload re-executed on every visitor.

- **New:** `Inquirex::SafeSource` — a default-deny **Prism AST allowlist**. The source is walked by recursive descent against an *expected shape*, so a construct nobody anticipated is rejected by construction rather than by name. Public API: `SafeSource.validate(text)` (returns violations), `.safe?(text)`, `.validate!(text)`. Use it to audit stored definitions without evaluating them.
- **New:** `Inquirex::Errors::UnsafeSourceError < Inquirex::Errors::DefinitionError`, carrying `#violations`. Existing `rescue Inquirex::Errors::DefinitionError` clauses keep working; messages name the line and what was found.
- **New:** `Inquirex::SafeSource::Vocabulary` — the allowlist, bound to the builders that implement it (flow verbs from `Node::VERBS`, step types from `Node::TYPES`, rules from `DSL::RuleHelpers`, effect keywords from each `Actions` effect constructor). `Vocabulary.undeclared_names(scope)` reports DSL words with no allowlist decision, and the suite fails when it is non-empty. Downstream gems extend it with `register_scope` / `allow` / `exclude` instead of forking it.
- **Changed:** `Inquirex.load_dsl(text, unsafe: false, max_bytes:, max_depth:)`. Validation is on by default.
- Caps: 64 KiB of source and 24 levels of nesting, both overridable via `SafeSource.max_source_bytes=` / `.max_depth=` or per call.
- Also rejected in safe mode: a `__END__` data section, and an `# encoding:` magic comment naming anything other than UTF-8 or ASCII (validation and evaluation must agree on token boundaries, and in encodings whose multi-byte sequences may contain ASCII bytes that agreement depends on the comment).

**Breaking:** flows that use `compute`, a block-form `default`, `fallback` or an action's `run` no longer load through the default path — a Ruby block is arbitrary code and cannot be validated. The `webhook` action effect and `send_email text:/html: { file: "path" }` are excluded for the same class of reason: the webhook's destination host is authorized by the `allowed_domains` declared in the same untrusted document (and plain `http` to localhost is permitted), and the `file:` body form is `File.read` at definition time, i.e. arbitrary file disclosure with an attacker-chosen recipient.

**To opt out for source you control as code** — a `.rb` file in your own repository, a fixture, anything a developer wrote — pass `unsafe: true`:

```ruby
Inquirex.load_dsl(File.read("flows/tax_intake.rb"), unsafe: true)
```

If the text reached you over a network or out of a database, it is not trusted, whatever the flow needs. Audit what you already store with `Inquirex::SafeSource.validate` before upgrading.

### Optional questions: `required false` and `Engine#skip`

- `required false` DSL builder method on collecting steps (`ask`, `confirm`): marks a question as optional so widgets render a small Skip control. Default remains `required true`, so every existing flow is unchanged.
- `Node#required?` predicate; step JSON gains `"required": false` (omitted when true), round-tripping through `to_json` / `from_json`.
- `Engine#skip` — user-initiated skip of the current optional step: records the step's `default` (when declared) into the answers and accumulators exactly as if answered, marks the step id in the new `Engine#skipped` list, and advances through transitions like `#answer`. Raises `Errors::RequiredStepError` (new) on a required step, `NonCollectingStepError` on a display step.
- Skip without a default writes no answers entry (a missing key and `nil` branch identically in rules; the "declined" signal lives in `skipped`).
- `Engine#skipped` / `Engine#skipped?(step_id)` distinguish default-by-skip values from user-provided answers; the list survives `to_state` / `from_state` (string→symbol normalized) and is merged into `Engine#answers_with_metadata` under `:skipped`.
- Steps elided automatically by `skip_if` rules are NOT marked as skipped — auto-elision is flow logic, `#skip` is a user action (see docs/design/required-and-skip.md).
- `required` is allowlisted in safe mode (`SafeSource::Vocabulary`) with a boolean literal argument, so optional questions load through the default validating path.

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
