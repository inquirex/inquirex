# Tell 'just' to run bash, source our setup script, then execute the recipe
set shell := ["bash", "-c"]

version := `grep VERSION lib/inquirex/version.rb | awk '{print $3}' | tr -d '"' | tr -d '\n'`
# The `-` matters: `rbenv init bash` prints human instructions ("skipping
# ~/.bash_login: already configured"), which eval then tries to run, and the
# recipe dies with "skipping: command not found". `rbenv init - bash` prints
# the shell code that is meant to be eval'd.
rbenv   := 'eval "$(rbenv init - bash 2>/dev/null || true)"; bundle exec '
repo    := 'git@github.com:inquirex/inquirex.git'

# 1Password secret reference for the RubyGems TOTP, and the full path to `op`
# because a recipe does not inherit an interactive shell's PATH.
# The account is NOT named here: it is a private 1Password address and this
# file is public. `op` reads it from OP_ACCOUNT, exported by the ecosystem
# root's .envrc, which lives outside every repo. Two accounts are
# registered and only one holds the open-source-repos vault, so without
# OP_ACCOUNT the read can resolve against the wrong one, return nothing,
# and publish silently falls back to prompting mid-release.
op       := '/opt/homebrew/bin/op'
otp_ref  := 'op://open-source-repos/ruby-gems/one-time password?attribute=otp'

gem_name := 'inquirex'
gem_file := 'pkg/' + gem_name + '-' + version + '.gem'
gem_url  := 'https://rubygems.org/gems/' + gem_name

[no-exit-message]
recipes:
    just --choose

# Sync all dependencies
install:
    bin/setup

build: install

# Lint and reformat files
lint:
    {{ rbenv }} rubocop

# Lint and reformat files (-a) — pass -A as an argument
format *args:
    {{ rbenv }} rubocop -a {{ args }}
    /usr/bin/find . -name '*.md' -exec mdformat --wrap no {} \; -print

# Run all the tests
test *args: 
    export ENVIRONMENT=test; {{ rbenv }} rspec {{args}}

# Run tests with coverage
test-coverage *args:
    export ENVIRONMENT=test; export COVERAGE=true; {{ rbenv }} rspec {{ args }}

ci: lint test-coverage 

alias check-all := ci

clean:
    #!/usr/bin/env bash
    @find . -name .DS_Store -delete -print || true
    @rm -rf tmp/*

# Run all lefthook pre-commit hooks
lefthook:
    {{ rbenv }} lefthook run pre-commit --all-files

# Print current gem version
version:
    @echo "{{ version }}"

# Clobber
clobber: 
    {{ rbenv }} rake clobber

# Generate documentation
doc: 
    #!/usr/bin/env bash
    {{ rbenv }} rake doc

# `gem push` rather than `rake release`: release also guards the tree, tags and
# pushes git — which `just release` does deliberately and separately — and it
# gives no way to pass a 2FA code, so it always stopped to prompt.
#
# The code comes from 1Password unless one is passed in:
#
#   just publish            # read the code from 1Password
#   just publish 123456     # use this code
#
# `just publish-all` in inquirex-tools passes one, because a TOTP is single-use:
# four gems reading the same 30-second window would have the second push
# rejected as a replay.
#
# Build the .gem and push it to RubyGems, non-interactively
publish otp="": build
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(rbenv init - bash 2>/dev/null || true)"

    mkdir -p pkg
    gem build {{ gem_name }}.gemspec --output "{{ gem_file }}"

    # `|| true` is load-bearing: under `set -e` a failed `op read` — not signed
    # in to 1Password, item renamed, op not installed — would abort the recipe
    # before the prompting fallback below could run.
    otp="{{ otp }}"
    [[ -n "${otp}" ]] || otp=$({{ op }} read "{{ otp_ref }}" 2>/dev/null || true)

    if [[ -n "${otp}" ]]; then
      gem push "{{ gem_file }}" --otp "${otp}"
    else
      echo "rubygems: no OTP available — gem push will prompt if 2FA is required."
      gem push "{{ gem_file }}"
    fi

    # Only reachable when the push succeeded: `set -e` aborts the recipe on a
    # non-zero `gem push`, so the page never opens for a release that failed.
    echo "published {{ gem_name }} {{ version }} → {{ gem_url }}"
    open "{{ gem_url }}" 2>/dev/null || xdg-open "{{ gem_url }}" 2>/dev/null || true

# Tag v{{ version }}, publish the GH release, & refresh the Homebrew tap.
release:
    git fetch --tags
    git tag -f "v{{ version }}"
    git push -f --tags
    gh release delete -y "v{{ version }}" --repo {{ repo }} 2>/dev/null || true
    gh release create "v{{ version }}" --generate-notes --repo {{ repo }}
