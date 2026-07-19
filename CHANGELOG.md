## [Unreleased]

## [0.6.0] - 2026-07-19

- Post-completion `action` DSL verb with an extensible effect registry
- `send_email` effect: builds `Mail::Message` objects (multipart text/HTML)
  from `{{field}}` templates into `Answers#outbox`; delivery is the host
  application's responsibility. The `mail` gem is a soft dependency.
- `run { |answers, outbox| ... }` escape-hatch effect (stripped from JSON)
- `webhook` effect: POSTs the answers envelope to a static https URL whose
  host must be covered by the new top-level `allowed_domains` declaration;
  enforcement runs in `Definition#validate!`, so tampered JSON definitions
  fail at rehydration
- `Inquirex::Actions::Runner` and `Inquirex::Actions.run(definition, answers)`
- Actions serialize to/from JSON with their rule gates
- `CompletionMetadata` (OpenStruct; `engine` and `engine_version` required)
  stamped by the engine at flow completion, enrichable by front-ends via the
  new `Engine#after_completion` hook, persisted in engine state, and merged
  into answers by `Engine#answers_with_metadata`

## [0.1.0] - 2026-04-13

- Initial release
