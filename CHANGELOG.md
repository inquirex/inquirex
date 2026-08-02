# Changelog

<<<<<<< HEAD
## [0.7.0] - 2026-07-30

### New: the top-level `send_email` verb (breaking)

A flow now declares the email it wants sent as a first-class part of the definition, with setter calls rather than a keyword hash — matching the DSL's existing idiom (`type :string`, `question "..."`):

```ruby
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
```

- **New:** `Inquirex::Email` — four opaque Liquid template strings (`to`, `from`, `subject`, `body_markdown`), serialized under the definition's `"emails"` key and rehydrated by `from_json`. `from` is optional; the other three are required.
- **The gem declares, the host renders.** `Email` never renders a template, never converts Markdown, never builds a `Mail::Message` and never delivers anything. Rendering would mean depending on a template engine, a Markdown converter and a mailer, and the core gem has no required runtime dependencies. Same division of labour as lambdas: the definition describes intent, the server-side host owns execution.
- **`body_markdown` is the single body source.** No `body_html`, no `body_text`. Markdown reads as plain text, so the host renders `text/plain` from it as-is and `text/html` from Markdown → HTML — one source, two MIME parts, nothing to keep in sync. There is no `markdown_to_html(...)` helper either: format is a property of the body, not a function you call on it.
- **New:** `Engine#on_complete_actions` — an ordered array of plain, JSON-serializable Hashes describing what the finished flow *asks* the host to do: `{"type" => "send_email", "to" => ..., "context" => {"answers" => ..., "accumulators" => ...}}`. The list is **advisory**: the gem sends nothing and tracks no delivery, and a host processes as much or as little of it as it likes, which is what keeps future action types (a webhook, a CRM push) additive. Templates are raw and travel with a context snapshot, so an entry is self-contained and can be enqueued and processed long after the engine is gone.
- **Liquid syntax is checked at definition time when Liquid happens to be loaded** (`Email.liquid_template_class` resolves `Liquid::Template` at call time, or nil). A host with Liquid gets authoring errors immediately; a host without it stores the strings verbatim. Liquid is not, and will not become, a dependency.
- Write bodies with a single-quoted heredoc (`<<~'TEXT'`): a plain `<<~TEXT` interpolates `#{}` in Ruby before the template ever reaches Liquid, which is the hole `SafeSource` exists to close.

### New: Liquid placeholders in every user-facing string

`question`, the `text` of `say` / `header` / `btw` / `warning`, and every `send_email` field may now carry Liquid `{{ }}` references to earlier answers and accumulator totals:

```ruby
question "Thanks {{ answers.name }}, where can we reach you?"
text     "Your estimate starts at ${{ accumulators.price | round: 2 }}."
```

**`{{ }}` is data; `#{}` is Ruby and stays forbidden.** This is the supported replacement for the thing authors otherwise reach for interpolation to do, so it *relieves* pressure on the security boundary instead of widening it — and it needed no allowlist change at all, because to the parser a placeholder is ordinary text inside a string literal.

- **New:** `Engine#render_context` — the plain, JSON-serializable Hash (`"answers"`, `"accumulators"`) a host binds when rendering. Take it fresh at **display time**, not at load time: answers accumulate as the wizard progresses. Symbol keys and values are normalized to Strings so the context survives a queue round-trip unchanged.
- **New:** `Inquirex::TemplateRefs` and `Definition#template_warnings` — a dependency-free scan naming references that resolve to nothing (`"step :email question references {{ answers.phone }}, which no step collects"`). Advisory, not fatal: Liquid renders an unknown reference as an empty string, and the scan is deliberately partial, passing over anything it cannot recognize rather than rejecting it on a guess.
- The gem stores strings verbatim; `Node#question` and `Node#text` still return the raw source.

### Removed: the dangerous action effects (breaking)

Deleted outright rather than merely refused in safe mode, which is the stronger guarantee — there is no `unsafe: true` that brings them back:

- **`webhook` effect and the top-level `allowed_domains` declaration.** The destination host was authorized by an allowlist declared in the *same untrusted document*, and plain `http` to localhost was permitted, making it an egress and SSRF primitive granted to whoever authored the text. Also gone: `Definition#allowed_host?`, `Definition#allowed_domains`, and `Actions::Base#validate_against`.
- **`run { |answers, outbox| ... }` and `Actions::Custom`** — arbitrary Ruby in a document that may have come from a database column.
- **`send_email text:`/`html:` given as `{ file: "path" }`** — `File.read` at definition time, i.e. arbitrary file disclosure with an attacker-chosen recipient.

With no non-serializable effect left, `Actions::Base#serializable?` and `Actions::Action#serializable?` are gone too, and `Definition#to_h` no longer filters actions.

### Deprecated: the `action` verb

`action ... do send_email ... end` still parses and still runs, so definitions hosts already store keep loading. It is deprecated in 0.7.0 and will be removed in 0.8.0; new flows use the top-level `send_email` declaration. Note that the effect's `{{field}}` templating (`Actions::Template`, resolved against `Answers#to_flat_h`) is *not* Liquid — that divergence is one of the reasons the verb is going away.

### `Inquirex.load_dsl` now validates before it evaluates (breaking)

`Inquirex.load_dsl(text)` was a bare `eval` of whatever it was handed. Any host that passed user-supplied text to it — a database column a customer edits, an upload, LLM output, a visual builder's "sync" button — was handing that user arbitrary Ruby execution in the loading process. This was confirmed live in a downstream Rails app: a backtick payload wrote a file and `ENV` was fully readable, and because the app memoised `load_dsl` per request, a stored payload re-executed on every visitor.

- **New:** `Inquirex::SafeSource` — a default-deny **Prism AST allowlist**. The source is walked by recursive descent against an *expected shape*, so a construct nobody anticipated is rejected by construction rather than by name. Public API: `SafeSource.validate(text)` (returns violations), `.safe?(text)`, `.validate!(text)`. Use it to audit stored definitions without evaluating them.
- **New:** `Inquirex::Errors::UnsafeSourceError < Inquirex::Errors::DefinitionError`, carrying `#violations`. Existing `rescue Inquirex::Errors::DefinitionError` clauses keep working; messages name the line and what was found.
- **New:** `Inquirex::SafeSource::Vocabulary` — the allowlist, bound to the builders that implement it (flow verbs from `Node::VERBS`, step types from `Node::TYPES`, rules from `DSL::RuleHelpers`, the `send_email` setters from `DSL::EmailBuilder`, effect keywords from each `Actions` effect constructor). `Vocabulary.undeclared_names(scope)` reports DSL words with no allowlist decision, and the suite fails when it is non-empty. Downstream gems extend it with `register_scope` / `allow` / `exclude` instead of forking it.
- **Changed:** `Inquirex.load_dsl(text, unsafe: false, max_bytes:, max_depth:)`. Validation is on by default.
- Caps: 64 KiB of source and 24 levels of nesting, both overridable via `SafeSource.max_source_bytes=` / `.max_depth=` or per call.
- Also rejected in safe mode: a `__END__` data section, and an `# encoding:` magic comment naming anything other than UTF-8 or ASCII (validation and evaluation must agree on token boundaries, and in encodings whose multi-byte sequences may contain ASCII bytes that agreement depends on the comment).

**Breaking:** flows that use `compute`, a block-form `default` or `fallback` no longer load through the default path — a Ruby block is arbitrary code and cannot be validated. The `webhook` effect, `allowed_domains`, an action's `run` and the `{ file: "path" }` body form are not merely excluded here: they were removed from the gem (see above).

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
=======
## [v0.7.0](https://github.com/inquirex/inquirex/tree/v0.7.0) (2026-07-31)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.6.1...v0.7.0)
>>>>>>> origin/main

**Merged pull requests:**

- Add required false and user-initiated Engine\#skip [\#4](https://github.com/inquirex/inquirex/pull/4) ([kigster](https://github.com/kigster))

## [v0.6.1](https://github.com/inquirex/inquirex/tree/v0.6.1) (2026-07-20)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.6.0...v0.6.1)

## [v0.6.0](https://github.com/inquirex/inquirex/tree/v0.6.0) (2026-07-20)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.5.0...v0.6.0)

**Merged pull requests:**

- Support for actions such as email send [\#3](https://github.com/inquirex/inquirex/pull/3) ([kigster](https://github.com/kigster))
- Add action DSL verb building emails into Answers\#outbox [\#2](https://github.com/inquirex/inquirex/pull/2) ([kigster](https://github.com/kigster))

## [v0.5.0](https://github.com/inquirex/inquirex/tree/v0.5.0) (2026-07-16)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.4.1...v0.5.0)

## [v0.4.1](https://github.com/inquirex/inquirex/tree/v0.4.1) (2026-07-13)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.4.0...v0.4.1)

## [v0.4.0](https://github.com/inquirex/inquirex/tree/v0.4.0) (2026-07-13)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.3.1...v0.4.0)

## [v0.3.1](https://github.com/inquirex/inquirex/tree/v0.3.1) (2026-04-15)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.3.0...v0.3.1)

## [v0.3.0](https://github.com/inquirex/inquirex/tree/v0.3.0) (2026-04-14)

[Full Changelog](https://github.com/inquirex/inquirex/compare/v0.2.0...v0.3.0)

**Merged pull requests:**

- Add accumulators for pricing and scoring [\#1](https://github.com/inquirex/inquirex/pull/1) ([kigster](https://github.com/kigster))

## [v0.2.0](https://github.com/inquirex/inquirex/tree/v0.2.0) (2026-04-13)

[Full Changelog](https://github.com/inquirex/inquirex/compare/a07eeaaa4d459139164e97c622d1d3038b28a5f5...v0.2.0)



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
