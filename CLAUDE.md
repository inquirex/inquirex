# CLAUDE.md — `inquirex` (core gem)

The foundation gem of the Inquirex family: a declarative, rules-driven questionnaire engine — flows as directed graphs with conditional branching, defined in a conversational Ruby DSL, serialized to JSON for cross-platform frontends. See `../CLAUDE.md` for the ecosystem picture (inquirex-ui, inquirex-tty, inquirex-js, inquirex-llm, qualified.at); this file covers only what is true *inside this repo*.

## Non-negotiable invariants

- **Zero third-party runtime dependencies.** The gemspec declares only `ostruct` (a stdlib bundled gem, needed by `CompletionMetadata`). `mail` is a *soft* dependency required lazily inside `SendEmail#to_mail`. Never add a runtime dependency; dev/test gems go in the `Gemfile`.
- **Rules are AST objects, never procs.** `Rules::{Contains,Equals,GreaterThan,LessThan,NotEmpty,All,Any}` serialize to `{ "op": ..., "field": ..., "value": ... }` and round-trip. The cross-site architecture depends on frontends evaluating rules locally.
- **Lambdas are stripped from JSON.** `default { }` blocks and `compute { }` are Ruby-only; serialization silently drops them.
- **`Definition` is frozen and thread-safe**; all mutation lives in `Engine`. `Engine#to_state` / `Engine.from_state` round-trip the full runtime state (answers, history, totals, suggestions, skipped, completion_metadata) — anything added to engine state must be registered with `Engine::StateSerializer` so string keys from JSON normalize back to symbols.
- **Wire format omits defaults**: `"required"` omitted when true, `"requires_server"` omitted when false, `"default"` omitted when nil, `"send_emails"` omitted when empty. Keep that convention for new fields.
- **`Inquirex.load_dsl` is an `eval`, guarded by `Inquirex::SafeSource` unless `unsafe: true`.** Treat `unsafe: true` as the explicit escape hatch for trusted, repo-authored source only.
- **Ruby >= 4.0** (gemspec). Use modern idioms: endless methods, pattern matching, `Data.define` for new value objects, anonymous block forwarding (`&`).

## The DSL surface (authoritative)

Flow level (`Inquirex.define id:, version: do ... end`, evaluated in `DSL::FlowBuilder`):

- `start :step_id`
- `meta title:, subtitle:, brand:, theme:` — snake_case theme keys are aliased to camelCase on the wire (`THEME_KEY_ALIASES`)
- `accumulator :name, type:, default:` — named running totals (pricing etc.)
- Step verbs: `ask`, `confirm` (collecting) · `say`, `header`, `btw`, `warning` (display)
- `send_email [if: rule] [inline kwargs] [do ... end]` — see below
- Rule helpers (via `DSL::RuleHelpers`): `contains`, `equals`, `greater_than`, `less_than`, `not_empty`, `all`, `any`

Step level (evaluated in `DSL::StepBuilder`): `type`, `question`, `text`, `options`, `default` (value or block), `required` (default true), `skip_if`, `transition to:, if_rule:, requires_server:`, `compute` (block), `widget type:, target:, **opts`, `accumulate` / `price`.

Types: `:string :text :integer :decimal :currency :boolean :enum :multi_enum :date :email :phone`.

Steps are configured **exclusively through builder methods inside the block** — the verbs take no option hashes. This is a deliberate grammar decision (see `docs/design/required-and-skip.md`); don't introduce an option-hash form.

### `send_email` — a declaration, not an action (as of 2026-08-02, unreleased)

The post-completion actions framework (`action`, `run`, `webhook`, `allowed_domains`, `Actions::*`, `Answers#outbox`) was **removed**. Post-completion behavior is the host application's job — qualified.at owns lead delivery (`LeadMailer`, `SiteWebhook`). Do not reintroduce any of it.

What remains is one top-level declaration:

```ruby
send_email if: not_empty(:email) do
  to      "{{email}}"
  from    "forms@agentica.group"
  subject "Thanks {{name}} — we got your inquiry"
  markdown_text <<~TEXT
    Hi {{name}},

    {{answers_summary}}
  TEXT
end
```

- Builder words: `to`, `from`, `cc`, `bcc`, `reply_to`, `subject`, `headers`, and bodies `text` / `markdown_text` / `html` (at least one body; `to` and `subject` required). Inline keyword form also works; block values win on conflict.
- Serializes under `"send_emails"` (array, in declaration order; gate under `"if"`). Rehydrates via `Definition#send_emails` → `Inquirex::SendEmail` objects with `#applicable?(answers_hash)` and `#to_mail(answers)`.
- **The gem never delivers** and **never renders Markdown to HTML** — `markdown_text` travels as Markdown; hosts render/deliver. In `#to_mail`, `text` (falling back to `markdown_text`, verbatim) is the plain part; `html` (auto-escaped interpolation) the HTML part.
- Templating is inert `{{field}}` interpolation only (`Inquirex::Template`, dot-notation keys against `Answers#to_flat_h`, plus `{{answers_summary}}`).
- Downstream consumers have **not** caught up yet (qualified.at `SafeDsl::Validator` still allowlists `action`; the webui printer emits neither). The obligations are itemized in `INQUIREX_VERSION_LOG.md` → Unreleased — read it before touching the wire format.

## Engine semantics worth knowing

- `answer` / `advance` / `skip` are the three user-driven step actions; `prefill!` is bulk out-of-band (hence the bang).
- `Engine#skip` (user declines an optional question) vs `skip_if` (flow logic auto-elides a step): **distinct concepts**. Auto-elided steps never enter `Engine#skipped`. Full rationale: `docs/design/required-and-skip.md`.
- Skip without a `default` writes **no** answers key (missing key ≡ nil for rules; the "declined" signal lives in `skipped`).
- `prefill!` treats multi-select extractions as *suggestions* the user confirms, single-select as facts.
- `after_completion` hooks let renderers attach `CompletionMetadata`; if none does, the engine stamps `engine: "inquirex", engine_version: VERSION`. `answers_with_metadata` merges `:completion_metadata` and `:skipped` into the answers.

## Repo layout

```text
lib/inquirex.rb              # require manifest + Inquirex.define / .load_dsl
lib/inquirex/
  dsl/                       # FlowBuilder, StepBuilder, SendEmailBuilder, RuleHelpers
  rules/                     # AST rule classes (base + 7 ops)
  engine.rb, engine/         # runtime + StateSerializer
  definition.rb, node.rb, transition.rb, evaluator.rb
  accumulator.rb             # Accumulator + Accumulation (lookup/per_selection/per_unit/flat)
  answers.rb                 # nested-hash wrapper (dot access, to_flat_h) — never OpenStruct
  send_email.rb, template.rb # completion email declaration + {{field}} rendering
  completion_metadata.rb     # OpenStruct subclass (the reason for the ostruct dep)
  widget_hint.rb, widget_registry.rb
  validation/                # pluggable answer validation (NullAdapter default)
  graph/mermaid_exporter.rb
docs/design/                 # design notes (required-and-skip.md)
examples/                    # runnable: 01 JSON dump, 02 mermaid, 03 send_email
INQUIREX_VERSION_LOG.md      # HAND-WRITTEN family log — never regenerate/overwrite
CHANGELOG.md                 # generated (github_changelog_generator) — disposable
```

## Testing and tooling

- `just test` / `just test-coverage` / `just lint` / `just format` / `just ci`. Bare `bundle exec rspec` works; run everything with `BUNDLE_GEMFILE=$PWD/Gemfile` from this directory (sibling repos share a shell too easily) and under `direnv exec .` in non-interactive shells.
- RSpec style: `subject(:x)` + `let`, `rspec-its` one-liners (`its(:code) { is_expected.to eq(...) }`), no local variables in examples. Monkey-patching is disabled (`disable_monkey_patching!`).
- Caution: inside `Inquirex.define` blocks in specs, `subject "..."` is the **SendEmailBuilder setter**, not RSpec's subject — rubocop-rspec false-positives there are silenced with inline disables.
- Coverage: SimpleCov writes `docs/badges/coverage_badge.svg` from `spec_helper.rb`'s `at_exit`. The bar is >95% line coverage.
- Lefthook pre-commit runs rubocop, `just test`, codespell, mdformat, detect-secrets. Run `mdformat --wrap no <file>` on any Markdown you author.
- CI (`.github/workflows/main.yml`) is just `bundle exec rake` (spec) on Ruby 4.0.2.
- YARD documentation is required on every new module/class/method/attr (`bundle exec yard stats --list-undoc` must not lose coverage; `just doc` builds it).

## Versioning and releasing

- This gem is in the **lockstep set** (`inquirex`, `inquirex-llm`, `inquirex-tools`, `inquirex-widget` — the npm widget formerly published as `@kigster/inquirex-js` — and `inquirex-webui` share one version; `inquirex-tty` is excluded). Never bump `lib/inquirex/version.rb` alone — use `inquirex versions --set X.Y.Z` from inquirex-tools, and versions only go forward.
- Every wire-format or DSL-vocabulary change gets a curated entry in `INQUIREX_VERSION_LOG.md` (what it means, what each consumer must do). PR-level noise goes to the generated `CHANGELOG.md` via `inquirex changelogs`.
- `just publish` → `rake release`; `just release` tags and creates the GitHub release. `rake build` first runs the `permissions` task (world-readable chmod for vendored installs).
- The gemspec enumerates files with `Dir.glob`, not `git ls-files` — deliberate, so the gem installs as a vendored path gem inside slim Docker images. Keep new top-level files out of the gem unless added to that glob.
